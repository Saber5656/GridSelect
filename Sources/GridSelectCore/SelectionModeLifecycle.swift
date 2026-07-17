public enum SelectionPermissionStatus: Equatable, Sendable {
    case granted
    case required
}

public enum SelectionOverlayResult: Equatable, Sendable {
    case confirmed(SelectionRectangle)
    case boundConfirmed(SelectionRectangle, BoundSelectionContext)
    case copyFinished(SelectionCopyResult)
    case cancelled
    case sourceFailed(SelectionSourceFailure)
}

public enum SelectionCopyRequest: Equatable, Sendable {
    case unbound(SelectionRectangle)
    case bound(
        SelectionRectangle,
        BoundSelectionContext,
        GridCopyAuthorization
    )
}

public enum SelectionCopyResult: Equatable, Sendable {
    case completed
    case cancelled
    case permissionRequired
    case failed(SelectionModeFailure)
}

public enum SelectionSourceFailure: Equatable, Sendable {
    case permissionRequired
    case secureInputUnsupported
    case sourceContextInvalid
    case unsupportedText
}

public struct SelectionSourceFailureError: Error, Equatable, Sendable {
    public let failure: SelectionSourceFailure

    public init(_ failure: SelectionSourceFailure) {
        self.failure = failure
    }
}

public enum SelectionModeFailure: Equatable, Sendable {
    case shortcutRegistrationFailed
    case listenerDisabled
    case overlayFailed
    case extractionFailed
    case clipboardWriteFailed
    case secureInputUnsupported
    case sourceContextInvalid
    case unsupportedText
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
    case sourceCaptureFailed(GridActivation, SelectionSourceFailure)
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
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void,
        onCopyRequested: @escaping @MainActor @Sendable (
            SelectionCopyRequest
        ) async -> SelectionCopyResult
    ) async throws -> SelectionOverlayResult

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
        onReady: @escaping @MainActor @Sendable () -> [GridHandoffCommand]?,
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult {
        try await select(sourceContext: nil, onReady: onReady, onDrag: onDrag)
    }
}

public protocol RectangularTextExtracting: Sendable {
    func extractText(in rectangle: SelectionRectangle) async throws -> String

    func extractText(
        in rectangle: SelectionRectangle,
        boundContext: BoundSelectionContext
    ) async throws -> String

    func discardBoundContexts(for sessionIdentity: SelectionSessionIdentity) async

    func validateCopyAuthorization(for boundContext: BoundSelectionContext?) async throws
}

public struct BoundTextExtractionUnavailableError: Error, Equatable, Sendable {
    public init() {}
}

public extension RectangularTextExtracting {
    func extractText(
        in rectangle: SelectionRectangle,
        boundContext: BoundSelectionContext
    ) async throws -> String {
        throw BoundTextExtractionUnavailableError()
    }

    func discardBoundContexts(for sessionIdentity: SelectionSessionIdentity) async {}

    func validateCopyAuthorization(for boundContext: BoundSelectionContext?) async throws {
        if boundContext != nil {
            throw BoundTextExtractionUnavailableError()
        }
    }
}

@MainActor
public protocol ClipboardWriting: AnyObject {
    func writePlainText(_ text: String) throws
}

@MainActor
public final class SelectionModeCoordinator {
    public private(set) var state: SelectionModeState = .idle
    public private(set) var shortcutRegistrationError: (any Error)?

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
    private var activeCopySessionID: Int?
    private var activeSourceContext: ActivationSourceContext?
    private var activeHandoffRequired = false
    private var sessionTasks: [Int: Task<Void, Never>] = [:]
    private var nextContextCleanupID: UInt64 = 0
    private var contextCleanupTasks: [UInt64: Task<Void, Never>] = [:]

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
            shortcutRegistrationError = nil
            if state == .failed(.shortcutRegistrationFailed)
                || state == .failed(.listenerDisabled)
            {
                transition(to: .idle)
            }
            return true
        } catch {
            shortcutRegistrationError = error
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
            discardRejectedSourceContext(sourceContext)
            return false
        }

        guard permissionChecker.selectionPermissionStatus == .granted else {
            discardRejectedSourceContext(sourceContext)
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
        if activeCopySessionID == sessionID {
            activeCopySessionID = nil
        }
        clearActiveSourceContext()
        activeHandoffRequired = false
        sessionTasks[sessionID]?.cancel()
        overlay.dismissSelection()
        transition(to: .cancelled)
        return true
    }

    public func reportSourceFailure(_ failure: SelectionSourceFailure) {
        guard activeSessionID == nil else {
            return
        }
        transition(to: state(for: failure))
    }

    public func shutdown() {
        activeSessionID = nil
        activeCopySessionID = nil
        clearActiveSourceContext()
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
        let cleanupTasks = Array(contextCleanupTasks.values)
        for task in cleanupTasks {
            await task.value
        }
    }

    func waitForContextCleanup() async {
        let cleanupTasks = Array(contextCleanupTasks.values)
        for task in cleanupTasks {
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
                },
                onCopyRequested: { [weak self] request in
                    guard let self else {
                        return .cancelled
                    }
                    return await self.processCopyRequest(
                        request,
                        sessionID: sessionID
                    )
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

        switch overlayResult {
        case .cancelled:
            overlay.dismissSelection()
            finish(with: .cancelled, sessionID: sessionID)
        case let .sourceFailed(failure):
            overlay.dismissSelection()
            finish(with: state(for: failure), sessionID: sessionID)
        case let .copyFinished(result):
            overlay.dismissSelection()
            finish(with: state(for: result), sessionID: sessionID)
        case .confirmed, .boundConfirmed:
            // The callback-aware protocol converts copy requests into a
            // terminal result before returning to the coordinator.
            overlay.dismissSelection()
            finish(with: .failed(.overlayFailed), sessionID: sessionID)
        }
    }

    private func processCopyRequest(
        _ request: SelectionCopyRequest,
        sessionID: Int
    ) async -> SelectionCopyResult {
        guard isCurrent(sessionID), activeCopySessionID == nil else {
            return .cancelled
        }
        activeCopySessionID = sessionID
        defer {
            if activeCopySessionID == sessionID {
                activeCopySessionID = nil
            }
        }
        switch request {
        case let .unbound(rectangle):
            guard activeSourceContext == nil else {
                return .failed(.extractionFailed)
            }
            return await processConfirmedSelection(
                rectangle,
                sessionID: sessionID
            )
        case let .bound(rectangle, boundContext, authorization):
            guard let activeSourceContext,
                  authorization.activation == boundContext.activation,
                  boundContext.activation == activeSourceContext.activation,
                  let sessionIdentity = boundContext.sessionIdentity,
                  sessionIdentity == activeSourceContext.sessionIdentity,
                  boundContext.source == activeSourceContext.source,
                  boundContext.sourceWindowFrame == activeSourceContext.sourceWindowFrame
            else {
                return .failed(.extractionFailed)
            }
            return await processConfirmedSelection(
                rectangle,
                boundContext: boundContext,
                sessionID: sessionID
            )
        }
    }

    private func processConfirmedSelection(
        _ rectangle: SelectionRectangle,
        boundContext: BoundSelectionContext? = nil,
        sessionID: Int
    ) async -> SelectionCopyResult {
        guard !rectangle.isEmpty else {
            return .cancelled
        }

        transition(to: .confirmed(rectangle), for: sessionID)
        guard isCurrent(sessionID), !Task.isCancelled else {
            return .cancelled
        }

        transition(to: .extracting(rectangle), for: sessionID)
        guard isCurrent(sessionID), !Task.isCancelled else {
            return .cancelled
        }

        let text: String
        do {
            if let boundContext {
                text = try await extractor.extractText(
                    in: rectangle,
                    boundContext: boundContext
                )
            } else {
                text = try await extractor.extractText(in: rectangle)
            }
        } catch is CancellationError {
            return .cancelled
        } catch is SelectionPermissionRequiredError {
            return .permissionRequired
        } catch let error as SelectionSourceFailureError {
            return result(for: error.failure)
        } catch {
            return .failed(.extractionFailed)
        }

        guard isCurrent(sessionID), !Task.isCancelled else {
            return .cancelled
        }

        guard permissionChecker.selectionPermissionStatus == .granted else {
            return .permissionRequired
        }

        guard case let .plainText(clipboardText) = clipboardFormatter.formatExtractedText(text) else {
            return .cancelled
        }

        transition(to: .copying, for: sessionID)
        guard isCurrent(sessionID), !Task.isCancelled else {
            return .cancelled
        }

        guard permissionChecker.selectionPermissionStatus == .granted else {
            return .permissionRequired
        }

        do {
            try await extractor.validateCopyAuthorization(for: boundContext)
        } catch is CancellationError {
            return .cancelled
        } catch is SelectionPermissionRequiredError {
            return .permissionRequired
        } catch let error as SelectionSourceFailureError {
            return result(for: error.failure)
        } catch {
            return .failed(.extractionFailed)
        }

        guard isCurrent(sessionID), !Task.isCancelled else {
            return .cancelled
        }

        guard permissionChecker.selectionPermissionStatus == .granted else {
            return .permissionRequired
        }

        do {
            try clipboard.writePlainText(clipboardText)
        } catch {
            return .failed(.clipboardWriteFailed)
        }

        return .completed
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
        case let .sourceCaptureFailed(_, failure):
            guard activeSessionID == nil else {
                return
            }
            transition(to: state(for: failure))
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

    private func state(for failure: SelectionSourceFailure) -> SelectionModeState {
        switch failure {
        case .permissionRequired:
            return .permissionRequired
        case .secureInputUnsupported:
            return .failed(.secureInputUnsupported)
        case .sourceContextInvalid:
            return .failed(.sourceContextInvalid)
        case .unsupportedText:
            return .failed(.unsupportedText)
        }
    }

    private func result(for failure: SelectionSourceFailure) -> SelectionCopyResult {
        switch state(for: failure) {
        case .permissionRequired:
            return .permissionRequired
        case let .failed(failure):
            return .failed(failure)
        case .idle, .selecting, .dragging, .confirmed, .extracting, .copying,
             .completed, .cancelled:
            return .failed(.extractionFailed)
        }
    }

    private func state(for result: SelectionCopyResult) -> SelectionModeState {
        switch result {
        case .completed:
            return .completed
        case .cancelled:
            return .cancelled
        case .permissionRequired:
            return .permissionRequired
        case let .failed(failure):
            return .failed(failure)
        }
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
        if activeCopySessionID == sessionID {
            activeCopySessionID = nil
        }
        clearActiveSourceContext()
        activeHandoffRequired = false
        transition(to: finalState)
    }

    private func clearActiveSourceContext() {
        guard let context = activeSourceContext else {
            return
        }
        if activeHandoffRequired {
            shortcut.cancelHandoff(for: context.activation, reason: .setupFailed)
        }
        activeSourceContext = nil
        discardRejectedSourceContext(context)
    }

    private func discardRejectedSourceContext(_ context: ActivationSourceContext?) {
        guard let sessionIdentity = context?.sessionIdentity else {
            return
        }
        nextContextCleanupID &+= 1
        let cleanupID = nextContextCleanupID
        let cleanupTask = Task { @MainActor [weak self, extractor] in
            await extractor.discardBoundContexts(for: sessionIdentity)
            self?.contextCleanupTasks[cleanupID] = nil
        }
        contextCleanupTasks[cleanupID] = cleanupTask
    }
}
