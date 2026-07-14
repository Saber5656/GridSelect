public enum SelectionPermissionStatus: Equatable, Sendable {
    case granted
    case required
}

public enum SelectionOverlayResult: Equatable, Sendable {
    case confirmed(SelectionRectangle)
    case boundConfirmed(SelectionRectangle, BoundSelectionContext)
    case cancelled
}

public enum SelectionModeFailure: Equatable, Sendable {
    case shortcutRegistrationFailed
    case listenerDisabled
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
    func registerEventHandler(
        _ handler: @escaping @MainActor @Sendable (SelectionShortcutEvent) -> Void
    ) throws

    func completeHandoff(for activation: GridActivation) -> [GridHandoffCommand]?

    func cancelHandoff(
        for activation: GridActivation,
        reason: GridActivationCancellationReason
    )

    func unregister()
}

public enum SelectionShortcutEvent: Equatable, Sendable {
    case activated(ActivationSourceContext)
    case handoffCancelled(GridActivation, GridActivationCancellationReason)
    case listenerDisabled
}

public extension SelectionShortcutRegistering {
    func completeHandoff(for activation: GridActivation) -> [GridHandoffCommand]? {
        []
    }

    func cancelHandoff(
        for activation: GridActivation,
        reason: GridActivationCancellationReason
    ) {}
}

@MainActor
public protocol SelectionPermissionChecking: AnyObject {
    var selectionPermissionStatus: SelectionPermissionStatus { get }
}

@MainActor
public protocol SelectionOverlayPresenting: AnyObject {
    func select(
        sourceContext: ActivationSourceContext?,
        onReady: @escaping @MainActor @Sendable () -> [GridHandoffCommand]?,
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult

    func select(
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult

    func dismissSelection()
}

public extension SelectionOverlayPresenting {
    func select(
        sourceContext: ActivationSourceContext?,
        onReady: @escaping @MainActor @Sendable () -> [GridHandoffCommand]?,
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult {
        guard onReady() != nil else {
            return .cancelled
        }
        return try await select(onDrag: onDrag)
    }

    func select(
        onReady: @escaping @MainActor @Sendable () -> [GridHandoffCommand]?,
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult {
        try await select(sourceContext: nil, onReady: onReady, onDrag: onDrag)
    }
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
    private var activeSourceContext: ActivationSourceContext?
    private var activeHandoffRequired = false
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
            try shortcut.registerEventHandler { [weak self] event in
                self?.handleShortcutEvent(
                    event,
                    registrationGeneration: registrationGeneration
                )
            }
            isShortcutInstalled = true
            if state == .failed(.shortcutRegistrationFailed)
                || state == .failed(.listenerDisabled)
            {
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
        activate(with: nil, requiresHandoff: false)
    }

    public func activate(sourceContext: ActivationSourceContext) -> Bool {
        activate(with: sourceContext, requiresHandoff: false)
    }

    private func activate(
        with sourceContext: ActivationSourceContext?,
        requiresHandoff: Bool
    ) -> Bool {
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
        activeSourceContext = sourceContext
        activeHandoffRequired = requiresHandoff
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
        if let activeSourceContext {
            shortcut.cancelHandoff(for: activeSourceContext.activation, reason: .setupFailed)
            self.activeSourceContext = nil
        }
        activeHandoffRequired = false
        sessionTasks[sessionID]?.cancel()
        overlay.dismissSelection()
        transition(to: .cancelled)
        return true
    }

    public func shutdown() {
        activeSessionID = nil
        if let activeSourceContext {
            shortcut.cancelHandoff(for: activeSourceContext.activation, reason: .setupFailed)
            self.activeSourceContext = nil
        }
        activeHandoffRequired = false
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
            overlayResult = try await overlay.select(
                sourceContext: activeSourceContext,
                onReady: { [weak self] in
                    self?.completeHandoff(for: sessionID)
                },
                onDrag: { [weak self] rectangle in
                    self?.handleDrag(rectangle, sessionID: sessionID)
                }
            )
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
            guard activeSourceContext == nil else {
                // The production Double-Shift path must never fall back to
                // copy-time hit testing. Issue #14 supplies bound extraction.
                finish(with: .failed(.extractionFailed), sessionID: sessionID)
                return
            }
            await processConfirmedSelection(rectangle, sessionID: sessionID)
        case let .boundConfirmed(rectangle, boundContext):
            guard let activeSourceContext,
                  boundContext.activation == activeSourceContext.activation,
                  boundContext.source == activeSourceContext.source
            else {
                finish(with: .failed(.extractionFailed), sessionID: sessionID)
                return
            }
            // Fail closed until Issue #14 changes the extractor port to accept
            // and revalidate this exact bound element at copy time.
            _ = rectangle
            finish(with: .failed(.extractionFailed), sessionID: sessionID)
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

    private func handleShortcutEvent(
        _ event: SelectionShortcutEvent,
        registrationGeneration: Int
    ) {
        guard isShortcutInstalled,
              shortcutGeneration == registrationGeneration
        else {
            return
        }
        switch event {
        case let .activated(sourceContext):
            guard activate(with: sourceContext, requiresHandoff: true) else {
                shortcut.cancelHandoff(
                    for: sourceContext.activation,
                    reason: .setupFailed
                )
                return
            }
        case let .handoffCancelled(activation, _):
            guard activeSourceContext?.activation == activation else {
                return
            }
            cancel()
        case .listenerDisabled:
            isShortcutInstalled = false
            shortcutGeneration += 1
            shortcut.unregister()
            if activeSessionID != nil {
                _ = cancel()
            }
            transition(to: .failed(.listenerDisabled))
        }
    }

    private func completeHandoff(for sessionID: Int) -> [GridHandoffCommand]? {
        guard isCurrent(sessionID) else {
            return nil
        }
        guard activeHandoffRequired else {
            return []
        }
        guard let activeSourceContext else {
            return []
        }
        guard let commands = shortcut.completeHandoff(
            for: activeSourceContext.activation
        ) else {
            return nil
        }
        activeHandoffRequired = false
        return commands
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
        if let activeSourceContext {
            shortcut.cancelHandoff(for: activeSourceContext.activation, reason: .setupFailed)
            self.activeSourceContext = nil
        }
        activeHandoffRequired = false
        transition(to: finalState)
    }
}
