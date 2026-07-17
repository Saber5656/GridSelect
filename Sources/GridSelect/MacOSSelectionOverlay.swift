import AppKit
import GridSelectCore

enum MacOSSelectionOverlayError: Error, Equatable {
    case alreadySelecting
    case noScreensAvailable
}

@MainActor
final class MacOSSelectionOverlay: SelectionOverlayPresenting {
    private let minimumSelectionSize: Double
    private let panelLevel: NSWindow.Level

    private var panels: [SelectionOverlayPanel] = []
    private var localKeyMonitor: Any?
    private var displayChangeObserver: NSObjectProtocol?
    private var ownershipLossObserver: NSObjectProtocol?
    private var continuation: CheckedContinuation<SelectionOverlayResult, any Error>?
    private var onDrag: (@MainActor @Sendable (SelectionRectangle) -> Void)?
    private var frozenRectangle: SelectionRectangle?
    private var deferredHandoffCommands: [GridHandoffCommand] = []

    init(
        minimumSelectionSize: Double = 4,
        panelLevel: NSWindow.Level = .statusBar
    ) {
        self.minimumSelectionSize = minimumSelectionSize
        self.panelLevel = panelLevel
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
        guard continuation == nil else {
            throw MacOSSelectionOverlayError.alreadySelecting
        }
        guard !NSScreen.screens.isEmpty else {
            throw MacOSSelectionOverlayError.noScreensAvailable
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.onDrag = onDrag
                presentPanels(preferredDisplayID: preferredDisplayID(for: sourceContext))
                guard verifyInputOwnership(), let commands = onReady() else {
                    finish(with: .cancelled)
                    return
                }
                monitorOwnershipLoss()
                applyHandoffCommands(commands)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(with: .cancelled)
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
        for command in commands {
            switch command {
            case .cancelRequested:
                finish(with: .cancelled)
                return
            case .copyRequested:
                confirmFrozenSelectionIfPossible()
            case .freeze, .move:
                // Issue #13 drains these into its caret/grid interaction model.
                // Retain semantic commands until that adapter consumes them;
                // never replay them to the source application.
                deferredHandoffCommands.append(command)
            }
        }
    }

    func dismissSelection() {
        finish(with: .cancelled)
    }

    private func presentPanels(preferredDisplayID: UInt32?) {
        panels = NSScreen.screens.map(makePanel)

        let preferredScreen = preferredDisplayID.flatMap { preferredDisplayID in
            NSScreen.screens.first(where: { displayID(for: $0) == preferredDisplayID })
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let owningPanel = panels.first(where: { $0.screen === preferredScreen }),
              let contentView = owningPanel.contentView
        else {
            finish(with: .cancelled)
            return
        }
        owningPanel.makeKey()
        owningPanel.makeFirstResponder(contentView)

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else {
                return event
            }
            guard self.verifyInputOwnership() else {
                self.finish(with: .cancelled)
                return nil
            }
            if event.keyCode == 53 {
                self.finish(with: .cancelled)
                return nil
            }
            if event.keyCode == 8, event.modifierFlags.contains(.command) {
                self.confirmFrozenSelectionIfPossible()
                return nil
            }
            return event
        }

        displayChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.finish(with: .cancelled)
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

    private func monitorOwnershipLoss() {
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
                self?.finish(with: .cancelled)
            }
        }
    }

    private func freeze(_ rectangle: SelectionRectangle) {
        frozenRectangle = rectangle
    }

    private func confirmFrozenSelectionIfPossible() {
        guard let frozenRectangle, !frozenRectangle.isEmpty else {
            return
        }
        finish(with: .confirmed(frozenRectangle))
    }

    private func makePanel(for screen: NSScreen) -> SelectionOverlayPanel {
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
        view.onDrag = { [weak self] rectangle in
            self?.onDrag?(rectangle)
        }
        view.onCancel = { [weak self] in
            self?.finish(with: .cancelled)
        }
        view.onFreeze = { [weak self] rectangle in
            self?.freeze(rectangle)
        }
        view.onCopy = { [weak self] in
            self?.confirmFrozenSelectionIfPossible()
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
        panel.orderFrontRegardless()
        return panel
    }

    private func finish(with result: SelectionOverlayResult) {
        guard let continuation else {
            cleanup()
            return
        }

        self.continuation = nil
        cleanup()
        continuation.resume(returning: result)
    }

    private func cleanup() {
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
        frozenRectangle = nil
        deferredHandoffCommands.removeAll(keepingCapacity: false)
    }

    private func displayID(for screen: NSScreen) -> UInt32 {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? UInt32 ?? 0
    }
}

private final class SelectionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class SelectionOverlayView: NSView {
    var geometry: SelectionDragGeometry?
    var onDrag: ((SelectionRectangle) -> Void)?
    var onCancel: (() -> Void)?
    var onFreeze: ((SelectionRectangle) -> Void)?
    var onCopy: (() -> Void)?

    private var anchor: SelectionPoint?
    private var current: SelectionPoint?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = selectionPoint(for: event)
        anchor = point
        current = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
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
    }

    private func selectionPoint(for event: NSEvent) -> SelectionPoint {
        let point = convert(event.locationInWindow, from: nil)
        return SelectionPoint(x: point.x, y: point.y)
    }

    private func currentRectangle() -> SelectionRectangle? {
        guard let geometry, let anchor, let current else {
            return nil
        }
        return geometry.rectangle(from: anchor, to: current)
    }

    private func localRectangle() -> NSRect? {
        guard let geometry, let rectangle = currentRectangle() else {
            return nil
        }
        return NSRect(
            x: rectangle.x - geometry.screenOrigin.x,
            y: rectangle.y - geometry.screenOrigin.y,
            width: rectangle.width,
            height: rectangle.height
        )
    }
}
