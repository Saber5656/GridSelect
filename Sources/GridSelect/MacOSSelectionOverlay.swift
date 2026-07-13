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
    private var continuation: CheckedContinuation<SelectionOverlayResult, any Error>?
    private var onDrag: (@MainActor @Sendable (SelectionRectangle) -> Void)?

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
                presentPanels()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(with: .cancelled)
            }
        }
    }

    func dismissSelection() {
        finish(with: .cancelled)
    }

    private func presentPanels() {
        panels = NSScreen.screens.map(makePanel)

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard event.keyCode == 53 else {
                return event
            }
            self?.finish(with: .cancelled)
            return nil
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
        view.onConfirm = { [weak self] rectangle in
            self?.finish(with: .confirmed(rectangle))
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
        panel.makeKey()
        panel.makeFirstResponder(view)
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

        panels.forEach { panel in
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        onDrag = nil
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
    var onConfirm: ((SelectionRectangle) -> Void)?

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

        guard let geometry, let rectangle = currentRectangle(),
              geometry.isConfirmable(rectangle) else {
            onCancel?()
            return
        }
        onConfirm?(rectangle)
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        onCancel?()
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
