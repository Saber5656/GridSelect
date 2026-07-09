#!/usr/bin/env swift

import AppKit

enum OverlayLevel: String {
    case floating
    case statusBar
    case screenSaver

    var nsWindowLevel: NSWindow.Level {
        switch self {
        case .floating:
            return .floating
        case .statusBar:
            return .statusBar
        case .screenSaver:
            return .screenSaver
        }
    }
}

struct PrototypeConfiguration {
    var level: OverlayLevel = .statusBar
    var minimumSelectionSize: CGFloat = 4
    var diagnosticsOnly = false
    var autoCancelAfterSeconds: TimeInterval?

    static func parse(_ arguments: [String]) -> PrototypeConfiguration {
        var configuration = PrototypeConfiguration()

        for argument in arguments.dropFirst() {
            if argument == "--help" || argument == "-h" {
                printHelpAndExit()
            } else if argument == "--diagnostics" {
                configuration.diagnosticsOnly = true
            } else if argument.hasPrefix("--level=") {
                let value = String(argument.dropFirst("--level=".count))
                guard let level = OverlayLevel(rawValue: value) else {
                    fail("invalid --level value: \(value)")
                }
                configuration.level = level
            } else if argument.hasPrefix("--min-size=") {
                let value = String(argument.dropFirst("--min-size=".count))
                guard let size = Double(value), size > 0 else {
                    fail("invalid --min-size value: \(value)")
                }
                configuration.minimumSelectionSize = CGFloat(size)
            } else if argument.hasPrefix("--auto-cancel-after=") {
                let value = String(argument.dropFirst("--auto-cancel-after=".count))
                guard let seconds = Double(value), seconds > 0 else {
                    fail("invalid --auto-cancel-after value: \(value)")
                }
                configuration.autoCancelAfterSeconds = seconds
            } else {
                fail("unknown argument: \(argument)")
            }
        }

        return configuration
    }
}

func printHelpAndExit() -> Never {
    print(
        """
        Usage:
          swift spikes/macos-overlay/overlay-rectangle-prototype.swift [options]

        Options:
          --level=floating|statusBar|screenSaver
              Overlay window level to test. Default: statusBar.
          --min-size=<points>
              Minimum width and height before mouse-up confirms. Default: 4.
          --diagnostics
              Print screen/Spaces diagnostics and exit without showing overlays.
          --auto-cancel-after=<seconds>
              Show overlays, then cancel automatically. Useful for smoke tests.
          -h, --help
              Print this help.
        """
    )
    exit(0)
}

func fail(_ message: String) -> Never {
    fputs("error: \(message)\n", stderr)
    exit(2)
}

func displayID(for screen: NSScreen) -> CGDirectDisplayID {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    return screen.deviceDescription[key] as? CGDirectDisplayID ?? 0
}

func printScreenDiagnostics(level: OverlayLevel) {
    print("overlayLevel=\(level.rawValue)")
    print("screensHaveSeparateSpaces=\(NSScreen.screensHaveSeparateSpaces)")

    for (index, screen) in NSScreen.screens.enumerated() {
        print(
            "screen[\(index)] id=\(displayID(for: screen)) " +
                "frame=\(screen.frame) visibleFrame=\(screen.visibleFrame) " +
                "backingScaleFactor=\(screen.backingScaleFactor)"
        )
    }
}

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
    var minimumSelectionSize: CGFloat = 4
    var onCancel: (() -> Void)?
    var onConfirm: ((SelectionRect) -> Void)?

    private var anchor: CGPoint?
    private var current: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        anchor = clamped(convert(event.locationInWindow, from: nil))
        current = anchor
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = clamped(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = clamped(convert(event.locationInWindow, from: nil))
        guard let selection = selectionRect(),
              selection.rectInScreenPoints.width >= minimumSelectionSize,
              selection.rectInScreenPoints.height >= minimumSelectionSize else {
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

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
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
    let configuration: PrototypeConfiguration

    private var panels: [SelectionOverlayPanel] = []
    private var localKeyMonitor: Any?
    private var displayChangeObserver: NSObjectProtocol?

    init(configuration: PrototypeConfiguration) {
        self.configuration = configuration
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        printScreenDiagnostics(level: configuration.level)

        panels = NSScreen.screens.map { screen in
            let view = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.screenID = displayID(for: screen)
            view.minimumSelectionSize = configuration.minimumSelectionSize
            view.onCancel = { [weak self] in self?.finish(nil) }
            view.onConfirm = { [weak self] selection in self?.finish(selection) }

            let panel = SelectionOverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = configuration.level.nsWindowLevel
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

        displayChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("selection cancelled: display configuration changed")
            self?.finish(nil)
        }

        if let seconds = configuration.autoCancelAfterSeconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                print("selection cancelled: auto-cancel-after elapsed")
                self?.finish(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let displayChangeObserver {
            NotificationCenter.default.removeObserver(displayChangeObserver)
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
}

let configuration = PrototypeConfiguration.parse(CommandLine.arguments)
let app = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

if configuration.diagnosticsOnly {
    printScreenDiagnostics(level: configuration.level)
    exit(0)
}

let delegate = PrototypeAppDelegate(configuration: configuration)
app.delegate = delegate
app.run()
