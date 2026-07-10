#!/usr/bin/env swift

import AppKit
import Carbon.HIToolbox
import Foundation

private enum HotKeyPrototype {
    static let signature = fourCharacterCode("GSLT")
    static let hotKeyID = EventHotKeyID(signature: signature, id: 1)
    static let keyCode = UInt32(kVK_ANSI_G)
    static let modifiers = UInt32(cmdKey | shiftKey)
    static let shortcutLabel = "Command-Shift-G"

    static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { code, byte in
            (code << 8) + OSType(byte)
        }
    }
}

private final class ShortcutAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var activationCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        installHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "GridSelect HotKey"
        item.button?.toolTip = "Waiting for \(HotKeyPrototype.shortcutLabel)"

        let menu = NSMenu()
        menu.addItem(withTitle: "Shortcut: \(HotKeyPrototype.shortcutLabel)", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Status: waiting", action: nil, keyEquivalent: "").tag = 100
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func installHotKey() {
        var hotKeyEvent = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                let app = Unmanaged<ShortcutAppDelegate>.fromOpaque(userData).takeUnretainedValue()
                return app.handleHotKey(event)
            },
            1,
            &hotKeyEvent,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            fail("InstallEventHandler failed: \(handlerStatus)")
            return
        }

        let registerStatus = RegisterEventHotKey(
            HotKeyPrototype.keyCode,
            HotKeyPrototype.modifiers,
            HotKeyPrototype.hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            fail("RegisterEventHotKey failed: \(registerStatus)")
            return
        }

        print("Registered \(HotKeyPrototype.shortcutLabel). Press it to update the menu bar status item.")
    }

    private func handleHotKey(_ event: EventRef) -> OSStatus {
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
        guard status == noErr, receivedID.signature == HotKeyPrototype.signature,
              receivedID.id == HotKeyPrototype.hotKeyID.id else {
            return OSStatus(eventNotHandledErr)
        }

        activationCount += 1
        let message = "Triggered \(activationCount)"
        statusItem?.button?.title = "GridSelect \(activationCount)"
        statusItem?.button?.toolTip = "\(HotKeyPrototype.shortcutLabel) \(message)"
        statusItem?.menu?.item(withTag: 100)?.title = "Status: \(message)"
        NSApp.requestUserAttention(.informationalRequest)
        NSSound.beep()
        print("\(Date()) \(message)")
        return noErr
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func fail(_ message: String) {
        statusItem?.button?.title = "GridSelect failed"
        statusItem?.menu?.item(withTag: 100)?.title = "Status: \(message)"
        fputs("\(message)\n", stderr)
    }
}

private func runSmokeTest() -> Int32 {
    var hotKeyRef: EventHotKeyRef?
    let status = RegisterEventHotKey(
        HotKeyPrototype.keyCode,
        HotKeyPrototype.modifiers,
        HotKeyPrototype.hotKeyID,
        GetEventDispatcherTarget(),
        0,
        &hotKeyRef
    )

    if let hotKeyRef {
        UnregisterEventHotKey(hotKeyRef)
    }

    if status == noErr {
        print("smoke-test: registered and unregistered \(HotKeyPrototype.shortcutLabel)")
        return 0
    }

    fputs("smoke-test: RegisterEventHotKey failed with OSStatus \(status)\n", stderr)
    return 1
}

if CommandLine.arguments.contains("--help") {
    print("""
    GridSelect hot-key prototype

    Usage:
      swift spikes/macos-shortcut/hotkey-prototype.swift
      swift spikes/macos-shortcut/hotkey-prototype.swift --smoke-test

    Normal mode starts a menu-bar prototype. Press \(HotKeyPrototype.shortcutLabel)
    to update the menu-bar title, beep, and print an activation line.
    """)
    exit(0)
}

if CommandLine.arguments.contains("--smoke-test") {
    exit(runSmokeTest())
}

private let app = NSApplication.shared
private let delegate = ShortcutAppDelegate()
app.delegate = delegate
app.run()
