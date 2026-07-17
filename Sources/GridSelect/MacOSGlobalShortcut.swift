import AppKit
import CoreGraphics
import Foundation
import GridSelectCore

enum MacOSGlobalShortcutError: Error, Equatable, LocalizedError {
    case inputMonitoringRequired
    case eventTapCreationFailed
    case runLoopSourceCreationFailed

    var errorDescription: String? {
        switch self {
        case .inputMonitoringRequired:
            return "Input Monitoring permission is required for Double-Shift."
        case .eventTapCreationFailed:
            return "The Double-Shift input listener could not be created."
        case .runLoopSourceCreationFailed:
            return "The Double-Shift input listener could not be attached to the run loop."
        }
    }
}

@MainActor
final class MacOSGlobalShortcut: SelectionShortcutRegistering {
    static let displayName = "Double-Shift"

    private var eventHandler: (
        @MainActor @Sendable (SelectionShortcutEvent) -> Void
    )?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var callbackContext: MacOSGridEventTapContext?
    private var callbackContextPointer: UnsafeMutableRawPointer?
    private var effectRelay: MacOSGridEventEffectRelay?
    private var timeoutTasks: [UInt64: Task<Void, Never>] = [:]

    func registerEventHandler(
        _ handler: @escaping @MainActor @Sendable (SelectionShortcutEvent) -> Void
    ) throws {
        unregister()
        guard CGPreflightListenEventAccess() else {
            throw MacOSGlobalShortcutError.inputMonitoringRequired
        }

        let relay = MacOSGridEventEffectRelay { [weak self] effect in
            self?.deliver(effect)
        }
        let context = MacOSGridEventTapContext(
            doubleClickInterval: NSEvent.doubleClickInterval
        ) { effect in
            relay.submit(effect)
        }
        let contextPointer = Unmanaged.passRetained(context).toOpaque()
        let eventMask = Self.eventMask
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: contextPointer
        ) else {
            context.disable()
            Unmanaged<MacOSGridEventTapContext>
                .fromOpaque(contextPointer)
                .release()
            throw MacOSGlobalShortcutError.eventTapCreationFailed
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            context.disable()
            CFMachPortInvalidate(eventTap)
            Unmanaged<MacOSGridEventTapContext>
                .fromOpaque(contextPointer)
                .release()
            throw MacOSGlobalShortcutError.runLoopSourceCreationFailed
        }

        eventHandler = handler
        effectRelay = relay
        callbackContext = context
        callbackContextPointer = contextPointer
        self.eventTap = eventTap
        runLoopSource = source
        context.enable()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func completeHandoff(for activation: GridActivation) -> [GridHandoffCommand]? {
        let commands = callbackContext?.completeHandoff(
            for: activation,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        if commands != nil {
            cancelTimeout(for: activation)
        }
        return commands
    }

    func cancelHandoff(
        for activation: GridActivation,
        reason: GridActivationCancellationReason
    ) {
        callbackContext?.cancelHandoff(for: activation, reason: reason)
        cancelTimeout(for: activation)
    }

    func unregister() {
        eventHandler = nil
        effectRelay?.disable()
        effectRelay = nil
        timeoutTasks.values.forEach { $0.cancel() }
        timeoutTasks.removeAll()
        callbackContext?.disable()

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        callbackContext = nil
        if let callbackContextPointer {
            self.callbackContextPointer = nil
            Unmanaged<MacOSGridEventTapContext>
                .fromOpaque(callbackContextPointer)
                .release()
        }
    }

    private func deliver(_ effect: GridInputEffect) {
        guard let eventHandler else {
            return
        }
        switch effect {
        case let .activated(activation):
            scheduleTimeout(for: activation)
            guard let sourceContext = MacOSActivationSourceCapturer.capture(
                activation: activation
            ) else {
                cancelHandoff(for: activation, reason: .setupFailed)
                eventHandler(.handoffCancelled(activation, .setupFailed))
                return
            }
            eventHandler(.activated(sourceContext))
        case let .handoffCancelled(activation, reason):
            cancelTimeout(for: activation)
            eventHandler(.handoffCancelled(activation, reason))
        case let .listenerDisabled(activation):
            if let activation {
                cancelTimeout(for: activation)
            }
            eventHandler(.listenerDisabled)
        }
    }

    private func scheduleTimeout(for activation: GridActivation) {
        cancelTimeout(for: activation)
        timeoutTasks[activation.generation] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard let effect = self?.callbackContext?.expireHandoff(
                for: activation,
                timestamp: ProcessInfo.processInfo.systemUptime
            ) else {
                return
            }
            self?.deliver(effect)
        }
    }

    private func cancelTimeout(for activation: GridActivation) {
        timeoutTasks.removeValue(forKey: activation.generation)?.cancel()
    }

    private static let eventMask: CGEventMask = [
        CGEventType.flagsChanged,
        .keyDown,
        .keyUp,
        .tapDisabledByTimeout,
        .tapDisabledByUserInput,
    ].reduce(CGEventMask(0)) { mask, eventType in
        mask | (CGEventMask(1) << eventType.rawValue)
    }

    private static let eventTapCallback: CGEventTapCallBack = {
        _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let context = Unmanaged<MacOSGridEventTapContext>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        return context.process(type: type, event: event)
            ? Unmanaged.passUnretained(event)
            : nil
    }

    deinit {
        // Normal teardown is MainActor-owned `unregister()`. The callback context
        // is disabled first so a queued callback cannot publish after shutdown.
        // If normal teardown was skipped, intentionally retain the opaque callback
        // context rather than risking a use-after-free from a run-loop-retained tap.
        callbackContext?.disable()
    }
}

@MainActor
enum MacOSActivationSourceCapturer {
    static func capture(activation: GridActivation) -> ActivationSourceContext? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let processIdentifier = application.processIdentifier
        guard processIdentifier > 0,
              processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = frontmostWindow(for: processIdentifier)
        else {
            return nil
        }

        let displays = NSScreen.screens.compactMap { screen -> DisplayGeometry? in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let displayID = screen.deviceDescription[key] as? UInt32 else {
                return nil
            }
            let cgBounds = CGDisplayBounds(displayID)
            return DisplayGeometry(
                displayID: displayID,
                appKitFrame: ScreenRectangle(
                    x: screen.frame.origin.x,
                    y: screen.frame.origin.y,
                    width: screen.frame.width,
                    height: screen.frame.height
                ),
                coreGraphicsBounds: ScreenRectangle(
                    x: cgBounds.origin.x,
                    y: cgBounds.origin.y,
                    width: cgBounds.width,
                    height: cgBounds.height
                ),
                backingScale: screen.backingScaleFactor
            )
        }
        guard !displays.isEmpty else {
            return nil
        }
        return ActivationSourceContext(
            activation: activation,
            source: SelectionSourceIdentity(
                processIdentifier: processIdentifier,
                windowIdentifier: window.identifier
            ),
            sourceWindowFrame: ScreenRectangle(
                x: window.frame.origin.x,
                y: window.frame.origin.y,
                width: window.frame.width,
                height: window.frame.height
            ),
            displays: displays,
            caretCandidate: nil
        )
    }

    private struct WindowSnapshot {
        let identifier: UInt32
        let frame: CGRect
    }

    private static func frontmostWindow(for processIdentifier: pid_t) -> WindowSnapshot? {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }
        for window in rawWindows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                    == processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let identifier = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary
            else {
                continue
            }
            var frame = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bounds as CFDictionary, &frame),
                  frame.width > 0,
                  frame.height > 0
            else {
                continue
            }
            return WindowSnapshot(identifier: identifier, frame: frame)
        }
        return nil
    }
}

final class MacOSGridEventEffectRelay: @unchecked Sendable {
    private let lock = NSLock()
    private let handler: @MainActor @Sendable (GridInputEffect) -> Void
    private var pending: [GridInputEffect] = []
    private var isEnabled = true
    private var isDraining = false

    init(handler: @escaping @MainActor @Sendable (GridInputEffect) -> Void) {
        self.handler = handler
    }

    func submit(_ effect: GridInputEffect) {
        let shouldStart = lock.withLock { () -> Bool in
            guard isEnabled else {
                return false
            }
            pending.append(effect)
            guard !isDraining else {
                return false
            }
            isDraining = true
            return true
        }
        guard shouldStart else {
            return
        }
        Task { @MainActor [weak self] in
            self?.drain()
        }
    }

    func disable() {
        lock.withLock {
            isEnabled = false
            pending.removeAll(keepingCapacity: false)
        }
    }

    @MainActor
    private func drain() {
        while true {
            let effect = lock.withLock { () -> GridInputEffect? in
                guard isEnabled, !pending.isEmpty else {
                    isDraining = false
                    return nil
                }
                return pending.removeFirst()
            }
            guard let effect else {
                return
            }
            handler(effect)
        }
    }
}

final class MacOSGridEventTapContext: @unchecked Sendable {
    static let matchingKeyUpSuppressionTimeout: TimeInterval = 0.5

    private let lock = NSLock()
    private let effectHandler: @Sendable (GridInputEffect) -> Void
    private var machine: GridActivationInputMachine
    private var isEnabled = false
    private var suppressedKeyUps: [GridGuardedKey: TimeInterval] = [:]

    init(
        doubleClickInterval: TimeInterval,
        effectHandler: @escaping @Sendable (GridInputEffect) -> Void
    ) {
        machine = GridActivationInputMachine(doubleClickInterval: doubleClickInterval)
        self.effectHandler = effectHandler
    }

    func enable() {
        lock.withLock {
            isEnabled = true
        }
    }

    func disable() {
        let effect = lock.withLock { () -> GridInputEffect? in
            guard isEnabled else {
                return nil
            }
            isEnabled = false
            suppressedKeyUps.removeAll(keepingCapacity: false)
            return machine.disableListener()
        }
        deliver(effect)
    }

    /// Returns true when the original event must continue to the source app.
    func process(
        type: CGEventType,
        event: CGEvent,
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        let result = lock.withLock { () -> GridInputDisposition in
            guard isEnabled else {
                return .passThrough
            }
            suppressedKeyUps = suppressedKeyUps.filter { _, deadline in
                timestamp <= deadline
            }
            switch type {
            case .flagsChanged:
                return machine.handleShiftChange(
                    isDown: event.flags.contains(.maskShift),
                    timestamp: timestamp
                )
            case .keyDown:
                guard machine.requiresGuardedKeyClassification else {
                    return machine.handleUnclassifiedKeyDown()
                }
                let key = Self.classifyGuardedKey(event)
                let result = machine.handleGuardedKeyDown(
                    key,
                    timestamp: timestamp
                )
                if result.delivery == .consume, key != .other {
                    suppressedKeyUps[key] = timestamp
                        + Self.matchingKeyUpSuppressionTimeout
                }
                return result
            case .keyUp:
                guard !suppressedKeyUps.isEmpty else {
                    return .passThrough
                }
                let key = Self.classifyGuardedKeyUp(event)
                guard suppressedKeyUps.removeValue(forKey: key) != nil else {
                    return .passThrough
                }
                return .consume
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                isEnabled = false
                suppressedKeyUps.removeAll(keepingCapacity: false)
                return GridInputDisposition(
                    delivery: .passThrough,
                    effect: machine.disableListener()
                )
            default:
                return .passThrough
            }
        }
        deliver(result.effect)
        return result.delivery == .passThrough
    }

    func completeHandoff(
        for activation: GridActivation,
        timestamp: TimeInterval
    ) -> [GridHandoffCommand]? {
        lock.withLock {
            guard isEnabled else {
                return nil
            }
            return machine.completeHandoff(for: activation, timestamp: timestamp)
        }
    }

    func cancelHandoff(
        for activation: GridActivation,
        reason: GridActivationCancellationReason
    ) {
        lock.withLock {
            _ = machine.cancelHandoff(for: activation, reason: reason)
        }
    }

    func expireHandoff(
        for activation: GridActivation,
        timestamp: TimeInterval
    ) -> GridInputEffect? {
        lock.withLock {
            guard isEnabled else {
                return nil
            }
            return machine.expireHandoff(for: activation, timestamp: timestamp)
        }
    }

    private func deliver(_ effect: GridInputEffect?) {
        if let effect {
            effectHandler(effect)
        }
    }

    private static func classifyGuardedKey(_ event: CGEvent) -> GridGuardedKey {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch keyCode {
        case 123:
            return .arrow(.left)
        case 124:
            return .arrow(.right)
        case 125:
            return .arrow(.down)
        case 126:
            return .arrow(.up)
        case 53:
            return .escape
        case 8 where event.flags.contains(.maskCommand):
            return .commandC
        default:
            return .other
        }
    }

    private static func classifyGuardedKeyUp(_ event: CGEvent) -> GridGuardedKey {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch keyCode {
        case 123:
            return .arrow(.left)
        case 124:
            return .arrow(.right)
        case 125:
            return .arrow(.down)
        case 126:
            return .arrow(.up)
        case 53:
            return .escape
        case 8:
            return .commandC
        default:
            return .other
        }
    }
}
