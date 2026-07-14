public enum SelectionPermissionStatus: Equatable, Sendable {
    case granted
    case required
}

public enum SelectionOverlayResult: Equatable, Sendable {
    case confirmed(SelectionRectangle)
    case cancelled
}

public enum SelectionModeFailure: Equatable, Sendable {
    case shortcutRegistrationFailed
    case overlayFailed
    case extractionFailed
    case clipboardWriteFailed
}

public struct SelectionPermissionRequiredError: Error, Equatable, Sendable {
    public init() {}
}

public enum SelectionModeState: Equatable, Sendable {
    case idle
    case selecting
    case dragging(SelectionRectangle)
    case confirmed(SelectionRectangle)
    case extracting(SelectionRectangle)
    case copying
    case completed
    case cancelled
    case permissionRequired
    case failed(SelectionModeFailure)

    public var isActive: Bool {
        switch self {
        case .selecting, .dragging, .confirmed, .extracting, .copying:
            return true
        case .idle, .completed, .cancelled, .permissionRequired, .failed:
            return false
        }
    }
}

@MainActor
public protocol SelectionShortcutRegistering: AnyObject {
    func registerActivationHandler(
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) throws

    func unregister()
}

@MainActor
public protocol SelectionPermissionChecking: AnyObject {
    var selectionPermissionStatus: SelectionPermissionStatus { get }
}

@MainActor
public protocol SelectionOverlayPresenting: AnyObject {
    func select(
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult

    func dismissSelection()
}

public protocol RectangularTextExtracting: Sendable {
    func extractText(in rectangle: SelectionRectangle) async throws -> String
}

@MainActor
public protocol ClipboardWriting: AnyObject {
    func writePlainText(_ text: String) throws
}

@MainActor
public final class SelectionModeCoordinator {
    public private(set) var state: SelectionModeState = .idle

    private let shortcut: any SelectionShortcutRegistering
    private let permissionChecker: any SelectionPermissionChecking
    private let overlay: any SelectionOverlayPresenting
    private let extractor: any RectangularTextExtracting
    private let clipboard: any ClipboardWriting
    private let clipboardFormatter: ClipboardTextFormatter
    private let stateObserver: @MainActor @Sendable (SelectionModeState) -> Void

    private var isShortcutInstalled = false
    private var shortcutGeneration = 0
    private var nextSessionID = 0
    private var activeSessionID: Int?
    private var sessionTasks: [Int: Task<Void, Never>] = [:]

    public init(
        shortcut: any SelectionShortcutRegistering,
        permissionChecker: any SelectionPermissionChecking,
        overlay: any SelectionOverlayPresenting,
        extractor: any RectangularTextExtracting,
        clipboard: any ClipboardWriting,
        clipboardFormatter: ClipboardTextFormatter = ClipboardTextFormatter(),
        stateObserver: @escaping @MainActor @Sendable (SelectionModeState) -> Void = { _ in }
    ) {
        self.shortcut = shortcut
        self.permissionChecker = permissionChecker
        self.overlay = overlay
        self.extractor = extractor
        self.clipboard = clipboard
        self.clipboardFormatter = clipboardFormatter
        self.stateObserver = stateObserver
    }

    @discardableResult
    public func installShortcut() -> Bool {
        guard !isShortcutInstalled else {
            return true
        }

        shortcutGeneration += 1
        let registrationGeneration = shortcutGeneration
        do {
            try shortcut.registerActivationHandler { [weak self] in
                self?.handleShortcutActivation(generation: registrationGeneration)
            }
            isShortcutInstalled = true
            if state == .failed(.shortcutRegistrationFailed) {
                transition(to: .idle)
            }
            return true
        } catch {
            transition(to: .failed(.shortcutRegistrationFailed))
            return false
        }
    }

    @discardableResult
    public func activate() -> Bool {
        guard !state.isActive, activeSessionID == nil else {
            return false
        }

        guard permissionChecker.selectionPermissionStatus == .granted else {
            transition(to: .permissionRequired)
            return false
        }

        nextSessionID += 1
        let sessionID = nextSessionID
        activeSessionID = sessionID
        transition(to: .selecting)

        guard isCurrent(sessionID) else {
            return true
        }

        sessionTasks[sessionID] = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.runSelectionSession(sessionID: sessionID)
        }
        return true
    }

    @discardableResult
    public func cancel() -> Bool {
        guard let sessionID = activeSessionID else {
            return false
        }

        activeSessionID = nil
        sessionTasks[sessionID]?.cancel()
        overlay.dismissSelection()
        transition(to: .cancelled)
        return true
    }

    public func shutdown() {
        activeSessionID = nil
        sessionTasks.values.forEach { $0.cancel() }
        overlay.dismissSelection()

        shortcutGeneration += 1
        let shouldUnregisterShortcut = isShortcutInstalled
        isShortcutInstalled = false
        if shouldUnregisterShortcut {
            shortcut.unregister()
        }

        transition(to: .idle)
    }

    func waitForMostRecentSession() async {
        let task = sessionTasks[nextSessionID]
        await task?.value
    }

    func waitForAllSessionCleanup() async {
        let tasks = Array(sessionTasks.values)
        for task in tasks {
            await task.value
        }
    }

    private func runSelectionSession(sessionID: Int) async {
        defer {
            clearSessionTask(for: sessionID)
        }

        guard isCurrent(sessionID) else {
            return
        }
        guard !Task.isCancelled else {
            finish(with: .cancelled, sessionID: sessionID)
            return
        }

        let overlayResult: SelectionOverlayResult
        do {
            overlayResult = try await overlay.select { [weak self] rectangle in
                self?.handleDrag(rectangle, sessionID: sessionID)
            }
        } catch is CancellationError {
            dismissOverlay(for: sessionID)
            finish(with: .cancelled, sessionID: sessionID)
            return
        } catch {
            dismissOverlay(for: sessionID)
            finish(with: .failed(.overlayFailed), sessionID: sessionID)
            return
        }

        guard isCurrent(sessionID), !Task.isCancelled else {
            return
        }

        overlay.dismissSelection()
        switch overlayResult {
        case .cancelled:
            finish(with: .cancelled, sessionID: sessionID)
        case let .confirmed(rectangle):
            await processConfirmedSelection(rectangle, sessionID: sessionID)
        }
    }

    private func processConfirmedSelection(
        _ rectangle: SelectionRectangle,
        sessionID: Int
    ) async {
        guard !rectangle.isEmpty else {
            finish(with: .cancelled, sessionID: sessionID)
            return
        }

        transition(to: .confirmed(rectangle), for: sessionID)
        guard isCurrent(sessionID), !Task.isCancelled else {
            return
        }

        transition(to: .extracting(rectangle), for: sessionID)
        guard isCurrent(sessionID), !Task.isCancelled else {
            return
        }

        let text: String
        do {
            text = try await extractor.extractText(in: rectangle)
        } catch is CancellationError {
            finish(with: .cancelled, sessionID: sessionID)
            return
        } catch is SelectionPermissionRequiredError {
            finish(with: .permissionRequired, sessionID: sessionID)
            return
        } catch {
            finish(with: .failed(.extractionFailed), sessionID: sessionID)
            return
        }

        guard isCurrent(sessionID), !Task.isCancelled else {
            return
        }

        guard case let .plainText(clipboardText) = clipboardFormatter.formatExtractedText(text) else {
            finish(with: .cancelled, sessionID: sessionID)
            return
        }

        transition(to: .copying, for: sessionID)
        guard isCurrent(sessionID), !Task.isCancelled else {
            return
        }

        do {
            try clipboard.writePlainText(clipboardText)
        } catch {
            finish(with: .failed(.clipboardWriteFailed), sessionID: sessionID)
            return
        }

        finish(with: .completed, sessionID: sessionID)
    }

    private func isCurrent(_ sessionID: Int) -> Bool {
        activeSessionID == sessionID
    }

    private func handleShortcutActivation(generation: Int) {
        guard isShortcutInstalled, shortcutGeneration == generation else {
            return
        }
        activate()
    }

    private func transition(to newState: SelectionModeState, for sessionID: Int) {
        guard isCurrent(sessionID) else {
            return
        }
        transition(to: newState)
    }

    private func handleDrag(_ rectangle: SelectionRectangle, sessionID: Int) {
        guard isCurrent(sessionID) else {
            return
        }

        switch state {
        case .selecting, .dragging:
            transition(to: .dragging(rectangle))
        case .idle, .confirmed, .extracting, .copying, .completed, .cancelled,
             .permissionRequired, .failed:
            return
        }
    }

    private func transition(to newState: SelectionModeState) {
        state = newState
        stateObserver(newState)
    }

    private func dismissOverlay(for sessionID: Int) {
        guard isCurrent(sessionID) else {
            return
        }
        overlay.dismissSelection()
    }

    private func clearSessionTask(for sessionID: Int) {
        sessionTasks[sessionID] = nil
    }

    private func finish(with finalState: SelectionModeState, sessionID: Int) {
        guard isCurrent(sessionID) else {
            return
        }

        activeSessionID = nil
        transition(to: finalState)
    }
}
