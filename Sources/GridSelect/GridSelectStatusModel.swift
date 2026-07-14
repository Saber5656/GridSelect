import AppKit
import ApplicationServices
import Combine
import GridSelectCore

@MainActor
final class GridSelectStatusModel: ObservableObject {
    @Published private(set) var snapshot: GridSelectStatusSnapshot
    private let permissionStatusProvider: @MainActor () -> SelectionPermissionStatus

    init(
        permissionStatus: SelectionPermissionStatus = AccessibilityPermissionClient.status,
        shortcutStatus: ShortcutReadiness = .inactive(displayName: "⌘⇧G"),
        selectionState: SelectionModeState = .idle,
        permissionStatusProvider: @escaping @MainActor () -> SelectionPermissionStatus = {
            AccessibilityPermissionClient.status
        }
    ) {
        self.permissionStatusProvider = permissionStatusProvider
        snapshot = GridSelectStatusSnapshot(
            permissionStatus: permissionStatus,
            shortcutStatus: shortcutStatus,
            selectionState: selectionState
        )
    }

    func recheckPermission() {
        snapshot = snapshot.updating(
            permissionStatus: permissionStatusProvider()
        )
    }

    func requestAccessibilityAccess() {
        AccessibilityPermissionClient.requestAccess()
        recheckPermission()
    }

    func openAccessibilitySettings() {
        AccessibilityPermissionClient.openSettings()
    }

    func updateShortcutStatus(_ status: ShortcutReadiness) {
        snapshot = snapshot.updating(shortcutStatus: status)
    }

    func updateSelectionState(_ state: SelectionModeState) {
        snapshot = snapshot.updating(selectionState: state)
    }
}

enum AccessibilityPermissionClient {
    static var status: SelectionPermissionStatus {
        AXIsProcessTrusted() ? .granted : .required
    }

    static func requestAccess() {
        // The exported CFString global is not concurrency-annotated in older SDKs.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        let accessibilitySettings = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        if let accessibilitySettings,
           NSWorkspace.shared.open(accessibilitySettings) {
            return
        }

        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )
    }
}
