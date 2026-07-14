import Carbon.HIToolbox
import Foundation
import GridSelectCore

enum MacOSGlobalShortcutError: Error, Equatable, LocalizedError {
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)
    case previousRegistrationCouldNotBeRemoved

    var errorDescription: String? {
        switch self {
        case let .eventHandlerInstallationFailed(status):
            return "The global shortcut event handler could not be installed (\(status))."
        case let .registrationFailed(status):
            return "Command-Shift-G could not be registered (\(status))."
        case .previousRegistrationCouldNotBeRemoved:
            return "The previous global shortcut registration could not be removed safely."
        }
    }
}

@MainActor
final class MacOSGlobalShortcut: SelectionShortcutRegistering {
    static let displayName = "⌘⇧G"

    private static let signature = "GSLT".utf8.reduce(OSType(0)) { code, byte in
        (code << 8) + OSType(byte)
    }
    private static let identifier = EventHotKeyID(signature: signature, id: 1)

    private var activationHandler: (@MainActor @Sendable () -> Void)?
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandlerRef: EventHandlerRef?
    private nonisolated(unsafe) var callbackContextPointer: UnsafeMutableRawPointer?
    private var isQuarantined = false

    func registerActivationHandler(
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) throws {
        unregister()
        guard !isQuarantined,
              hotKeyRef == nil,
              eventHandlerRef == nil,
              callbackContextPointer == nil
        else {
            throw MacOSGlobalShortcutError.previousRegistrationCouldNotBeRemoved
        }

        let callbackContext = MacOSHotKeyCallbackContext { [weak self] in
            self?.activateFromCallback()
        }
        let callbackContextPointer = Unmanaged.passRetained(callbackContext).toOpaque()
        self.callbackContextPointer = callbackContextPointer

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                var receivedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedID
                )
                guard status == noErr,
                      receivedID.signature == MacOSGlobalShortcut.signature,
                      receivedID.id == MacOSGlobalShortcut.identifier.id
                else {
                    return OSStatus(eventNotHandledErr)
                }

                let context = Unmanaged<MacOSHotKeyCallbackContext>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                context.deliverIfEnabled()
                return noErr
            },
            1,
            &eventType,
            callbackContextPointer,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            releaseCallbackContextIfSafe()
            throw MacOSGlobalShortcutError.eventHandlerInstallationFailed(handlerStatus)
        }

        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_G),
            UInt32(cmdKey | shiftKey),
            Self.identifier,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard registrationStatus == noErr else {
            callbackContext.disable()
            if let eventHandlerRef {
                let removalStatus = RemoveEventHandler(eventHandlerRef)
                // Carbon invalidates EventHandlerRef after every removal attempt,
                // regardless of the returned status. Never reuse or remove it again.
                self.eventHandlerRef = nil
                if removalStatus != noErr {
                    isQuarantined = true
                }
            }
            releaseCallbackContextIfSafe()
            throw MacOSGlobalShortcutError.registrationFailed(registrationStatus)
        }

        activationHandler = handler
        callbackContext.enable()
    }

    func unregister() {
        activationHandler = nil
        callbackContext?.disable()
        if let hotKeyRef {
            if UnregisterEventHotKey(hotKeyRef) == noErr {
                self.hotKeyRef = nil
            }
        }
        if let eventHandlerRef {
            let removalStatus = RemoveEventHandler(eventHandlerRef)
            // The reference is invalid after the call even when removal fails.
            self.eventHandlerRef = nil
            if removalStatus != noErr {
                isQuarantined = true
            }
        }
        releaseCallbackContextIfSafe()
    }

    fileprivate func activateFromCallback() {
        activationHandler?()
    }

    private var callbackContext: MacOSHotKeyCallbackContext? {
        guard let callbackContextPointer else {
            return nil
        }
        return Unmanaged<MacOSHotKeyCallbackContext>
            .fromOpaque(callbackContextPointer)
            .takeUnretainedValue()
    }

    private func releaseCallbackContextIfSafe() {
        guard !isQuarantined,
              eventHandlerRef == nil,
              let callbackContextPointer
        else {
            return
        }
        self.callbackContextPointer = nil
        Unmanaged<MacOSHotKeyCallbackContext>
            .fromOpaque(callbackContextPointer)
            .release()
    }

    deinit {
        activationHandler = nil
        if let callbackContextPointer {
            Unmanaged<MacOSHotKeyCallbackContext>
                .fromOpaque(callbackContextPointer)
                .takeUnretainedValue()
                .disable()
        }
        // Carbon registration APIs are not thread-safe. Normal cleanup belongs
        // to MainActor unregister(); deinit only disables and intentionally
        // retains any remaining callback context to avoid use-after-free.
    }
}

final class MacOSHotKeyCallbackContext: @unchecked Sendable {
    private let lock = NSLock()
    private let handler: @MainActor @Sendable () -> Void
    private var isEnabled = false

    init(handler: @escaping @MainActor @Sendable () -> Void) {
        self.handler = handler
    }

    func enable() {
        lock.lock()
        isEnabled = true
        lock.unlock()
    }

    func disable() {
        lock.lock()
        isEnabled = false
        lock.unlock()
    }

    func deliverIfEnabled() {
        Task { @MainActor [self] in
            if enabled() {
                handler()
            }
        }
    }

    private func enabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isEnabled
    }
}
