import AppKit
import GridSelectCore

enum MacOSSelectionOverlayError: Error, Equatable {
    case alreadySelecting
    case noScreensAvailable
}

protocol MacOSGridMouseAnchorResolving: AnyObject, Sendable {
    func resolveMouseAnchor(
        at appKitScreenPoint: SelectionPoint,
        sourceContext: ActivationSourceContext
    ) -> MacOSGridMouseAnchorResolution

    func discardMouseAnchor(
        _ candidate: GridMouseAnchorCandidate,
        sourceContext: ActivationSourceContext
    )
}

enum MacOSGridMouseAnchorResolution: Equatable, Sendable {
    case resolved(GridMouseAnchorCandidate)
    case unavailable
    case rejected(SelectionSourceFailure)
}

private final class UnavailableGridMouseAnchorResolver:
    MacOSGridMouseAnchorResolving,
    @unchecked Sendable
{
    func resolveMouseAnchor(
        at appKitScreenPoint: SelectionPoint,
        sourceContext: ActivationSourceContext
    ) -> MacOSGridMouseAnchorResolution {
        .unavailable
    }

    func discardMouseAnchor(
        _ candidate: GridMouseAnchorCandidate,
        sourceContext: ActivationSourceContext
    ) {}
}

@MainActor
final class MacOSSelectionOverlay: SelectionOverlayPresenting {
    private struct PendingMouseResolution {
        let requestID: UInt64
        let sessionGeneration: UInt64
        let displayID: UInt32
        let anchorPoint: SelectionPoint
        var latestPoint: SelectionPoint
        var ended: Bool
    }

    private struct IgnoredMouseGesture {
        let sessionGeneration: UInt64
        let displayID: UInt32
    }

    private let minimumSelectionSize: Double
    private let panelLevel: NSWindow.Level
    private let mouseAnchorResolver: any MacOSGridMouseAnchorResolving

    private var panels: [SelectionOverlayPanel] = []
    private var localKeyMonitor: Any?
    private var displayChangeObserver: NSObjectProtocol?
    private var ownershipLossObserver: NSObjectProtocol?
    private var continuation: CheckedContinuation<SelectionOverlayResult, any Error>?
    private var onDrag: (@MainActor @Sendable (SelectionRectangle) -> Void)?
    private var onCopyRequested: (@MainActor @Sendable (
        SelectionCopyRequest
    ) async -> SelectionCopyResult)?
    private var copyTask: Task<Void, Never>?
    private var frozenRectangle: SelectionRectangle?
    private var sourceContext: ActivationSourceContext?
    private var gridInteraction: GridOverlayInteraction?
    private var nextMouseResolutionID: UInt64 = 0
    private var pendingMouseResolution: PendingMouseResolution?
    private var ignoredMouseGesture: IgnoredMouseGesture?
    private var mouseResolutionTask: Task<Void, Never>?
    private var sessionGuard = GridOverlaySessionGuard()

    init(
        minimumSelectionSize: Double = 4,
        panelLevel: NSWindow.Level = .statusBar,
        mouseAnchorResolver: (any MacOSGridMouseAnchorResolving)? = nil
    ) {
        self.minimumSelectionSize = minimumSelectionSize
        self.panelLevel = panelLevel
        self.mouseAnchorResolver = mouseAnchorResolver
            ?? UnavailableGridMouseAnchorResolver()
    }

    func select(
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult {
        try await select(sourceContext: nil, onReady: { [] }, onDrag: onDrag)
    }

    func select(
        sourceContext: ActivationSourceContext?,
        onReady: @escaping @MainActor @Sendable () -> [GridHandoffCommand]?,
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult {
        try await selectSession(
            sourceContext: sourceContext,
            onReady: onReady,
            onDrag: onDrag,
            onCopyRequested: nil
        )
    }

    func select(
        sourceContext: ActivationSourceContext?,
        onReady: @escaping @MainActor @Sendable () -> [GridHandoffCommand]?,
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void,
        onCopyRequested: @escaping @MainActor @Sendable (
            SelectionCopyRequest
        ) async -> SelectionCopyResult
    ) async throws -> SelectionOverlayResult {
        try await selectSession(
            sourceContext: sourceContext,
            onReady: onReady,
            onDrag: onDrag,
            onCopyRequested: onCopyRequested
        )
    }

    private func selectSession(
        sourceContext: ActivationSourceContext?,
        onReady: @escaping @MainActor @Sendable () -> [GridHandoffCommand]?,
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void,
        onCopyRequested: (@MainActor @Sendable (
            SelectionCopyRequest
        ) async -> SelectionCopyResult)?
    ) async throws -> SelectionOverlayResult {
        guard continuation == nil else {
            throw MacOSSelectionOverlayError.alreadySelecting
        }
        guard !NSScreen.screens.isEmpty else {
            throw MacOSSelectionOverlayError.noScreensAvailable
        }
        let sessionGeneration = sessionGuard.begin()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.onDrag = onDrag
                self.onCopyRequested = onCopyRequested
                self.sourceContext = sourceContext
                gridInteraction = sourceContext.map(GridOverlayInteraction.init)
                presentPanels(
                    preferredDisplayID: preferredDisplayID(for: sourceContext),
                    sessionGeneration: sessionGeneration
                )
                if let sourceContext, sourceContext.caretCandidate == nil {
                    setGridStatusMessage(
                        "Keyboard caret unavailable — click and drag in supported monospace text"
                    )
                }
                guard verifyInputOwnership(), let commands = onReady() else {
                    finish(with: .cancelled, ifCurrent: sessionGeneration)
                    return
                }
                monitorOwnershipLoss(sessionGeneration: sessionGeneration)
                if let rectangle = gridInteraction?.currentRectangle {
                    renderGridRectangle(rectangle)
                    onDrag(rectangle)
                }
                applyHandoffCommands(commands)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(with: .cancelled, ifCurrent: sessionGeneration)
            }
        }
    }

    func select(
        onReady: @escaping @MainActor @Sendable () -> [GridHandoffCommand]?,
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult {
        try await select(sourceContext: nil, onReady: onReady, onDrag: onDrag)
    }

    private func verifyInputOwnership() -> Bool {
        let owningPanels = panels.filter(\.isKeyWindow)
        guard owningPanels.count == 1,
              let panel = owningPanels.first,
              let contentView = panel.contentView
        else {
            return false
        }
        return panel.firstResponder === contentView
    }

    private func applyHandoffCommands(_ commands: [GridHandoffCommand]) {
        if var interaction = gridInteraction {
            let effects = interaction.applyHandoffCommands(commands)
            gridInteraction = interaction
            for effect in effects {
                applyGridEffect(effect)
                guard continuation != nil else {
                    return
                }
            }
            return
        }
        for command in commands {
            switch command {
            case .cancelRequested:
                finish(with: .cancelled)
                return
            case .copyRequested:
                confirmFrozenSelectionIfPossible()
            case .freeze, .move:
                break
            }
        }
    }

    func dismissSelection() {
        finish(with: .cancelled)
    }

    private func presentPanels(
        preferredDisplayID: UInt32?,
        sessionGeneration: UInt64
    ) {
        let screens = NSScreen.screens
        panels = screens.map {
            makePanel(for: $0, sessionGeneration: sessionGeneration)
        }

        let preferredScreen: NSScreen?
        if let preferredDisplayID {
            preferredScreen = screens.first {
                displayID(for: $0) == preferredDisplayID
            }
        } else {
            preferredScreen = NSScreen.main ?? screens.first
        }
        guard let owningPanel = panels.first(where: { $0.screen === preferredScreen }),
              let contentView = owningPanel.contentView
        else {
            finish(with: .cancelled)
            return
        }
        owningPanel.makeKey()
        owningPanel.makeFirstResponder(contentView)

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) {
            [weak self] event in
            guard let self,
                  self.sessionGuard.isCurrent(sessionGeneration)
            else {
                return event
            }
            guard self.verifyInputOwnership() else {
                self.finish(with: .cancelled, ifCurrent: sessionGeneration)
                return event.type == .flagsChanged ? event : nil
            }
            if event.type == .flagsChanged {
                if !event.modifierFlags.contains(.shift) {
                    self.freezeGridSelection()
                }
                // The approved contract passes the second-Shift release through.
                return event
            }
            if event.keyCode == 53 {
                self.finish(with: .cancelled)
                return nil
            }
            if event.keyCode == 8, event.modifierFlags.contains(.command) {
                self.confirmFrozenSelectionIfPossible()
                return nil
            }
            if let direction = Self.gridDirection(for: event.keyCode) {
                self.moveGridSelection(direction)
                return nil
            }
            return event
        }

        displayChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finish(with: .cancelled, ifCurrent: sessionGeneration)
            }
        }
    }

    private func preferredDisplayID(
        for context: ActivationSourceContext?
    ) -> UInt32? {
        guard let context else {
            return nil
        }
        if let caretDisplayID = context.caretCandidate?.displayID {
            return caretDisplayID
        }
        let centerX = context.sourceWindowFrame.minX + context.sourceWindowFrame.width / 2
        let centerY = context.sourceWindowFrame.minY + context.sourceWindowFrame.height / 2
        return context.displays.first(where: { display in
            let bounds = display.coreGraphicsBounds
            return centerX >= bounds.minX && centerX < bounds.maxX
                && centerY >= bounds.minY && centerY < bounds.maxY
        })?.displayID
    }

    private func monitorOwnershipLoss(sessionGeneration: UInt64) {
        guard let owningPanel = panels.first(where: \.isKeyWindow) else {
            finish(with: .cancelled)
            return
        }
        ownershipLossObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: owningPanel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.sessionGuard.isCurrent(sessionGeneration),
                      !self.verifyInputOwnership()
                else {
                    return
                }
                self.finish(with: .cancelled, ifCurrent: sessionGeneration)
            }
        }
    }

    private func stopOwnershipLossMonitoring() {
        guard let ownershipLossObserver else {
            return
        }
        NotificationCenter.default.removeObserver(ownershipLossObserver)
        self.ownershipLossObserver = nil
    }

    private func freeze(_ rectangle: SelectionRectangle) {
        frozenRectangle = rectangle
    }

    private func confirmFrozenSelectionIfPossible() {
        if var interaction = gridInteraction {
            let effect = interaction.requestCopy()
            gridInteraction = interaction
            if let effect {
                applyGridEffect(effect)
            }
            return
        }
        guard let frozenRectangle, !frozenRectangle.isEmpty else {
            return
        }
        guard onCopyRequested != nil else {
            finish(with: .confirmed(frozenRectangle))
            return
        }
        beginCopy(.unbound(frozenRectangle))
    }

    private func makePanel(
        for screen: NSScreen,
        sessionGeneration: UInt64
    ) -> SelectionOverlayPanel {
        let geometry = SelectionDragGeometry(
            displayID: displayID(for: screen),
            screenOrigin: SelectionPoint(
                x: screen.frame.origin.x,
                y: screen.frame.origin.y
            ),
            screenWidth: screen.frame.width,
            screenHeight: screen.frame.height,
            minimumSelectionSize: minimumSelectionSize
        )
        let view = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.geometry = geometry
        view.usesGridInteraction = sourceContext != nil
        view.onDrag = { [weak self] rectangle in
            guard self?.sessionGuard.isCurrent(sessionGeneration) == true else {
                return
            }
            self?.onDrag?(rectangle)
        }
        view.onCancel = { [weak self] in
            self?.finish(with: .cancelled, ifCurrent: sessionGeneration)
        }
        view.onFreeze = { [weak self] rectangle in
            guard self?.sessionGuard.isCurrent(sessionGeneration) == true else {
                return
            }
            self?.freeze(rectangle)
        }
        view.onCopy = { [weak self] in
            guard self?.sessionGuard.isCurrent(sessionGeneration) == true else {
                return
            }
            self?.confirmFrozenSelectionIfPossible()
        }
        view.onGridMouseDown = { [weak self] point in
            self?.beginGridMouseSelection(
                at: point,
                displayID: geometry.displayID,
                sessionGeneration: sessionGeneration
            )
        }
        view.onGridMouseDragged = { [weak self] point in
            self?.moveGridMouseSelection(
                to: point,
                displayID: geometry.displayID,
                sessionGeneration: sessionGeneration
            )
        }
        view.onGridMouseUp = { [weak self] point in
            self?.endGridMouseSelection(
                at: point,
                displayID: geometry.displayID,
                sessionGeneration: sessionGeneration
            )
        }

        let panel = SelectionOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = panelLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.contentView = view
        panel.displayID = geometry.displayID
        panel.orderFrontRegardless()
        return panel
    }

    private func finish(with result: SelectionOverlayResult) {
        guard let continuation else {
            cleanup()
            return
        }

        if case .cancelled = result,
           var interaction = gridInteraction,
           case let .copying(authorization) = interaction.lifecycle.state
        {
            _ = interaction.cancelCopy(authorization)
            gridInteraction = interaction
        }
        self.continuation = nil
        sessionGuard.invalidateCurrent()
        cleanup()
        continuation.resume(returning: result)
    }

    private func finish(
        with result: SelectionOverlayResult,
        ifCurrent sessionGeneration: UInt64
    ) {
        guard sessionGuard.isCurrent(sessionGeneration) else {
            return
        }
        finish(with: result)
    }

    private func cleanup() {
        mouseResolutionTask?.cancel()
        mouseResolutionTask = nil
        pendingMouseResolution = nil
        ignoredMouseGesture = nil
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let displayChangeObserver {
            NotificationCenter.default.removeObserver(displayChangeObserver)
            self.displayChangeObserver = nil
        }
        if let ownershipLossObserver {
            NotificationCenter.default.removeObserver(ownershipLossObserver)
            self.ownershipLossObserver = nil
        }

        panels.forEach { panel in
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        onDrag = nil
        onCopyRequested = nil
        copyTask?.cancel()
        copyTask = nil
        frozenRectangle = nil
        sourceContext = nil
        gridInteraction = nil
        sessionGuard.invalidateCurrent()
    }

    private func displayID(for screen: NSScreen) -> UInt32 {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? UInt32 ?? 0
    }

    private static func gridDirection(for keyCode: UInt16) -> GridDirection? {
        switch keyCode {
        case 123: .left
        case 124: .right
        case 125: .down
        case 126: .up
        default: nil
        }
    }

    private func moveGridSelection(_ direction: GridDirection) {
        guard var interaction = gridInteraction else {
            return
        }
        let effect = interaction.moveKeyboardFocus(direction)
        gridInteraction = interaction
        if let effect {
            applyGridEffect(effect)
        }
    }

    private func freezeGridSelection() {
        guard var interaction = gridInteraction else {
            return
        }
        let effect = interaction.freeze()
        gridInteraction = interaction
        if let effect {
            applyGridEffect(effect)
        }
    }

    private func beginGridMouseSelection(
        at point: SelectionPoint,
        displayID: UInt32,
        sessionGeneration: UInt64
    ) {
        guard sessionGuard.isCurrent(sessionGeneration) else {
            return
        }
        sessionGuard.endMouseDrag(generation: sessionGeneration)
        guard let sourceContext else {
            return
        }
        guard pendingMouseResolution == nil else {
            ignoredMouseGesture = IgnoredMouseGesture(
                sessionGeneration: sessionGeneration,
                displayID: displayID
            )
            return
        }
        nextMouseResolutionID &+= 1
        if nextMouseResolutionID == 0 {
            nextMouseResolutionID = 1
        }
        let requestID = nextMouseResolutionID
        pendingMouseResolution = PendingMouseResolution(
            requestID: requestID,
            sessionGeneration: sessionGeneration,
            displayID: displayID,
            anchorPoint: point,
            latestPoint: point,
            ended: false
        )
        let resolver = mouseAnchorResolver
        mouseResolutionTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard !Task.isCancelled else {
                return
            }
            let resolution = resolver.resolveMouseAnchor(
                at: point,
                sourceContext: sourceContext
            )
            if Task.isCancelled {
                if case let .resolved(candidate) = resolution {
                    resolver.discardMouseAnchor(
                        candidate,
                        sourceContext: sourceContext
                    )
                }
                return
            }
            let applied = await self?.applyMouseAnchorResolution(
                resolution,
                requestID: requestID
            ) ?? false
            if !applied, case let .resolved(candidate) = resolution {
                resolver.discardMouseAnchor(
                    candidate,
                    sourceContext: sourceContext
                )
            }
        }
    }

    private func applyMouseAnchorResolution(
        _ resolution: MacOSGridMouseAnchorResolution,
        requestID: UInt64
    ) -> Bool {
        guard let pending = pendingMouseResolution,
              pending.requestID == requestID,
              sessionGuard.isCurrent(pending.sessionGeneration)
        else {
            return false
        }
        pendingMouseResolution = nil
        mouseResolutionTask = nil
        let candidate: GridMouseAnchorCandidate
        switch resolution {
        case let .resolved(value):
            candidate = value
        case .unavailable:
            return true
        case let .rejected(failure):
            finish(with: .sourceFailed(failure), ifCurrent: pending.sessionGeneration)
            return true
        }
        guard candidate.viewport.displayID == pending.displayID,
              makeOwningPanelKey(
                  displayID: pending.displayID,
                  sessionGeneration: pending.sessionGeneration
              ),
              var interaction = gridInteraction
        else {
            finish(with: .cancelled, ifCurrent: pending.sessionGeneration)
            return false
        }
        let result = interaction.beginMouseSelection(
            candidate: candidate,
            at: pending.anchorPoint
        )
        gridInteraction = interaction
        switch result {
        case let .accepted(effect):
            _ = sessionGuard.beginMouseDrag(
                displayID: pending.displayID,
                generation: pending.sessionGeneration
            )
            applyGridEffect(effect)
            if pending.latestPoint != pending.anchorPoint {
                applyGridMouseFocus(
                    to: pending.latestPoint,
                    displayID: pending.displayID,
                    sessionGeneration: pending.sessionGeneration
                )
            }
            if pending.ended {
                freezeGridSelection()
                sessionGuard.endMouseDrag(generation: pending.sessionGeneration)
            }
        case .ignored:
            return false
        case .rejected:
            finish(with: .cancelled, ifCurrent: pending.sessionGeneration)
            return false
        }
        return true
    }

    private func moveGridMouseSelection(
        to point: SelectionPoint,
        displayID: UInt32,
        sessionGeneration: UInt64
    ) {
        if let ignored = ignoredMouseGesture,
           ignored.sessionGeneration == sessionGeneration,
           ignored.displayID == displayID
        {
            return
        }
        if var pending = pendingMouseResolution,
           pending.sessionGeneration == sessionGeneration,
           pending.displayID == displayID
        {
            pending.latestPoint = point
            pendingMouseResolution = pending
            return
        }
        applyGridMouseFocus(
            to: point,
            displayID: displayID,
            sessionGeneration: sessionGeneration
        )
    }

    private func applyGridMouseFocus(
        to point: SelectionPoint,
        displayID: UInt32,
        sessionGeneration: UInt64
    ) {
        guard sessionGuard.acceptsMouseEvent(
                  displayID: displayID,
                  generation: sessionGeneration
              ),
              var interaction = gridInteraction
        else {
            return
        }
        let effect = interaction.moveMouseFocus(to: point)
        gridInteraction = interaction
        if let effect {
            applyGridEffect(effect)
        }
    }

    private func endGridMouseSelection(
        at point: SelectionPoint,
        displayID: UInt32,
        sessionGeneration: UInt64
    ) {
        if let ignored = ignoredMouseGesture,
           ignored.sessionGeneration == sessionGeneration,
           ignored.displayID == displayID
        {
            ignoredMouseGesture = nil
            return
        }
        if var pending = pendingMouseResolution,
           pending.sessionGeneration == sessionGeneration,
           pending.displayID == displayID
        {
            pending.latestPoint = point
            pending.ended = true
            pendingMouseResolution = pending
            return
        }
        guard sessionGuard.acceptsMouseEvent(
                  displayID: displayID,
                  generation: sessionGeneration
              )
        else {
            return
        }
        moveGridMouseSelection(
            to: point,
            displayID: displayID,
            sessionGeneration: sessionGeneration
        )
        freezeGridSelection()
        sessionGuard.endMouseDrag(generation: sessionGeneration)
    }

    private func makeOwningPanelKey(
        displayID: UInt32,
        sessionGeneration: UInt64
    ) -> Bool {
        guard let panel = panels.first(where: { $0.displayID == displayID }),
              let contentView = panel.contentView
        else {
            return false
        }
        stopOwnershipLossMonitoring()
        panel.makeKey()
        panel.makeFirstResponder(contentView)
        guard verifyInputOwnership() else {
            return false
        }
        monitorOwnershipLoss(sessionGeneration: sessionGeneration)
        return true
    }

    private func applyGridEffect(_ effect: GridOverlayInteractionEffect) {
        switch effect {
        case let .selectionChanged(rectangle):
            setGridStatusMessage(nil)
            renderGridRectangle(rectangle)
            onDrag?(rectangle)
        case let .selectionFrozen(rectangle):
            setGridStatusMessage(nil)
            frozenRectangle = rectangle
            renderGridRectangle(rectangle)
            onDrag?(rectangle)
        case .selectAtLeastOneColumn:
            setGridStatusMessage("Select at least one column")
        case let .copyRequested(rectangle, context, authorization):
            guard onCopyRequested != nil else {
                finish(with: .boundConfirmed(rectangle, context))
                return
            }
            beginCopy(.bound(rectangle, context, authorization))
        case .cancelled:
            finish(with: .cancelled)
        }
    }

    private func renderGridRectangle(_ rectangle: SelectionRectangle) {
        for panel in panels {
            guard let view = panel.contentView as? SelectionOverlayView else {
                continue
            }
            view.renderedRectangle = panel.displayID == rectangle.displayID
                ? rectangle
                : nil
            view.needsDisplay = true
        }
    }

    private func setGridStatusMessage(_ message: String?) {
        for panel in panels {
            guard let view = panel.contentView as? SelectionOverlayView else {
                continue
            }
            view.statusMessage = message
            view.needsDisplay = true
        }
    }

    private func beginCopy(_ request: SelectionCopyRequest) {
        guard copyTask == nil,
              let onCopyRequested,
              let sessionGeneration = sessionGuard.activeGeneration
        else {
            return
        }
        setGridStatusMessage("Copying… Press Escape to cancel")
        copyTask = Task { @MainActor [weak self] in
            let result = await onCopyRequested(request)
            guard let self,
                  !Task.isCancelled,
                  self.sessionGuard.isCurrent(sessionGeneration)
            else {
                return
            }
            guard self.applyCopyResult(result, for: request) else {
                self.copyTask = nil
                return
            }
            self.copyTask = nil
            self.finish(
                with: .copyFinished(result),
                ifCurrent: sessionGeneration
            )
        }
    }

    private func applyCopyResult(
        _ result: SelectionCopyResult,
        for request: SelectionCopyRequest
    ) -> Bool {
        guard case let .bound(_, _, authorization) = request else {
            return true
        }
        guard var interaction = gridInteraction else {
            return false
        }
        let accepted: Bool
        switch result {
        case .completed:
            accepted = interaction.finishCopy(authorization, succeeded: true)
        case .cancelled:
            accepted = interaction.cancelCopy(authorization)
        case .permissionRequired, .failed:
            accepted = interaction.finishCopy(authorization, succeeded: false)
        }
        gridInteraction = interaction
        return accepted
    }
}

private final class SelectionOverlayPanel: NSPanel {
    var displayID: UInt32 = 0
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class SelectionOverlayView: NSView {
    var geometry: SelectionDragGeometry?
    var usesGridInteraction = false
    var renderedRectangle: SelectionRectangle?
    var statusMessage: String?
    var onDrag: ((SelectionRectangle) -> Void)?
    var onCancel: (() -> Void)?
    var onFreeze: ((SelectionRectangle) -> Void)?
    var onCopy: (() -> Void)?
    var onGridMouseDown: ((SelectionPoint) -> Void)?
    var onGridMouseDragged: ((SelectionPoint) -> Void)?
    var onGridMouseUp: ((SelectionPoint) -> Void)?

    private var anchor: SelectionPoint?
    private var current: SelectionPoint?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        if usesGridInteraction {
            onGridMouseDown?(globalSelectionPoint(for: event))
            return
        }
        let point = selectionPoint(for: event)
        anchor = point
        current = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if usesGridInteraction {
            onGridMouseDragged?(globalSelectionPoint(for: event))
            return
        }
        guard anchor != nil else {
            return
        }
        current = selectionPoint(for: event)
        needsDisplay = true
        if let rectangle = currentRectangle() {
            onDrag?(rectangle)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if usesGridInteraction {
            onGridMouseUp?(globalSelectionPoint(for: event))
            return
        }
        guard anchor != nil else {
            return
        }
        current = selectionPoint(for: event)
        needsDisplay = true

        guard let rectangle = currentRectangle() else {
            return
        }
        onFreeze?(rectangle)
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else if event.keyCode == 8, event.modifierFlags.contains(.command) {
            onCopy?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        guard let rectangle = localRectangle() else {
            if let statusMessage {
                drawStatusMessage(statusMessage, above: nil)
            }
            return
        }

        NSColor.systemBlue.withAlphaComponent(0.12).setFill()
        rectangle.fill()

        let halo = NSBezierPath(rect: rectangle.insetBy(dx: -1, dy: -1))
        halo.lineWidth = 4
        NSColor.black.withAlphaComponent(0.72).setStroke()
        halo.stroke()

        let border = NSBezierPath(rect: rectangle)
        border.lineWidth = 2
        NSColor.systemBlue.setStroke()
        border.stroke()

        if let statusMessage {
            drawStatusMessage(statusMessage, above: rectangle)
        }
    }

    private func selectionPoint(for event: NSEvent) -> SelectionPoint {
        let point = convert(event.locationInWindow, from: nil)
        return SelectionPoint(x: point.x, y: point.y)
    }

    private func globalSelectionPoint(for event: NSEvent) -> SelectionPoint {
        let local = selectionPoint(for: event)
        guard let geometry else {
            return local
        }
        return SelectionPoint(
            x: geometry.screenOrigin.x + local.x,
            y: geometry.screenOrigin.y + local.y
        )
    }

    private func currentRectangle() -> SelectionRectangle? {
        guard let geometry, let anchor, let current else {
            return nil
        }
        return geometry.rectangle(from: anchor, to: current)
    }

    private func localRectangle() -> NSRect? {
        guard let geometry,
              let rectangle = renderedRectangle ?? currentRectangle()
        else {
            return nil
        }
        return NSRect(
            x: rectangle.x - geometry.screenOrigin.x,
            y: rectangle.y - geometry.screenOrigin.y,
            width: rectangle.width,
            height: rectangle.height
        )
    }

    private func drawStatusMessage(_ message: String, above rectangle: NSRect?) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let text = message as NSString
        let textSize = text.size(withAttributes: attributes)
        let padding = NSSize(width: 10, height: 6)
        let bubbleSize = NSSize(
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )
        let proposedX = (rectangle?.midX ?? bounds.midX) - bubbleSize.width / 2
        let x = min(max(bounds.minX + 8, proposedX), bounds.maxX - bubbleSize.width - 8)
        let proposedY = rectangle.map { $0.maxY + 8 }
            ?? (bounds.midY - bubbleSize.height / 2)
        let y = min(proposedY, bounds.maxY - bubbleSize.height - 8)
        let bubble = NSRect(origin: NSPoint(x: x, y: y), size: bubbleSize)
        let path = NSBezierPath(roundedRect: bubble, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.82).setFill()
        path.fill()
        text.draw(
            at: NSPoint(x: bubble.minX + padding.width, y: bubble.minY + padding.height),
            withAttributes: attributes
        )
    }
}
