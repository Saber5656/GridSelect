#!/usr/bin/env swift

import AppKit

struct SelectionRect {
    var screenID: CGDirectDisplayID
    var rectInScreenPoints: CGRect
}

final class SelectionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SelectionOverlayView: NSView {
    var screenID: CGDirectDisplayID = 0
    var onCancel: (() -> Void)?
    var onConfirm: ((SelectionRect) -> Void)?

    private var anchor: CGPoint?
    private var current: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        current = anchor
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard let selection = selectionRect(), selection.rectInScreenPoints.width >= 4,
              selection.rectInScreenPoints.height >= 4 else {
            onCancel?()
            return
        }
        onConfirm?(selection)
    }

    override func keyDown(with event: NSEvent) {
        if handleKey(event) {
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        guard let rect = normalizedRectInView() else {
            return
        }

        NSColor.systemBlue.withAlphaComponent(0.12).setFill()
        rect.fill()

        let strokePath = NSBezierPath(rect: rect)
        strokePath.lineWidth = 2
        NSColor.systemBlue.setStroke()
        strokePath.stroke()
    }

    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            onCancel?()
            return true
        default:
            return false
        }
    }

    private func normalizedRectInView() -> NSRect? {
        guard let anchor, let current else {
            return nil
        }

        return NSRect(
            x: min(anchor.x, current.x),
            y: min(anchor.y, current.y),
            width: abs(anchor.x - current.x),
            height: abs(anchor.y - current.y)
        )
    }

    private func selectionRect() -> SelectionRect? {
        guard let window, let rectInView = normalizedRectInView() else {
            return nil
        }

        let rectInWindow = convert(rectInView, to: nil)
        let rectInScreen = window.convertToScreen(rectInWindow)
        return SelectionRect(screenID: screenID, rectInScreenPoints: rectInScreen)
    }
}

final class PrototypeAppDelegate: NSObject, NSApplicationDelegate {
    private var panels: [SelectionOverlayPanel] = []
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panels = NSScreen.screens.map { screen in
            let view = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.screenID = displayID(for: screen)
            view.onCancel = { [weak self] in self?.finish(nil) }
            view.onConfirm = { [weak self] selection in self?.finish(selection) }

            let panel = SelectionOverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = .statusBar
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

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else {
                return event
            }
            for panel in panels {
                if let view = panel.contentView as? SelectionOverlayView, view.handleKey(event) {
                    return nil
                }
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    private func finish(_ selection: SelectionRect?) {
        if let selection {
            print(
                "selection screenID=\(selection.screenID) " +
                    "x=\(selection.rectInScreenPoints.origin.x) " +
                    "y=\(selection.rectInScreenPoints.origin.y) " +
                    "w=\(selection.rectInScreenPoints.width) " +
                    "h=\(selection.rectInScreenPoints.height)"
            )
        } else {
            print("selection cancelled")
        }

        panels.forEach { $0.close() }
        NSApp.terminate(nil)
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID ?? 0
    }
}

let app = NSApplication.shared
let delegate = PrototypeAppDelegate()
app.delegate = delegate
app.run()
