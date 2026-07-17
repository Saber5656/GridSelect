import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import GridSelectCore

@MainActor
final class GridSelectStatusModel: ObservableObject {
    @Published private(set) var snapshot: GridSelectStatusSnapshot
    private let inputMonitoringStatusProvider: @MainActor () -> SelectionPermissionStatus
    private let permissionStatusProvider: @MainActor () -> SelectionPermissionStatus

    init(
        inputMonitoringStatus: SelectionPermissionStatus = InputMonitoringPermissionClient.status,
        permissionStatus: SelectionPermissionStatus = AccessibilityPermissionClient.status,
        shortcutStatus: ShortcutReadiness = .inactive(displayName: "Double-Shift"),
        selectionState: SelectionModeState = .idle,
        inputMonitoringStatusProvider: @escaping @MainActor () -> SelectionPermissionStatus = {
            InputMonitoringPermissionClient.status
        },
        permissionStatusProvider: @escaping @MainActor () -> SelectionPermissionStatus = {
            AccessibilityPermissionClient.status
        }
    ) {
        self.inputMonitoringStatusProvider = inputMonitoringStatusProvider
        self.permissionStatusProvider = permissionStatusProvider
        snapshot = GridSelectStatusSnapshot(
            inputMonitoringStatus: inputMonitoringStatus,
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

    func recheckInputMonitoring() {
        snapshot = snapshot.updating(
            inputMonitoringStatus: inputMonitoringStatusProvider()
        )
    }

    func recheckPermissions() {
        recheckInputMonitoring()
        recheckPermission()
    }

    func requestInputMonitoringAccess() {
        InputMonitoringPermissionClient.requestAccess()
        recheckInputMonitoring()
    }

    func openInputMonitoringSettings() {
        InputMonitoringPermissionClient.openSettings()
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

enum InputMonitoringPermissionClient {
    static var status: SelectionPermissionStatus {
        CGPreflightListenEventAccess() ? .granted : .required
    }

    static func requestAccess() {
        _ = CGRequestListenEventAccess()
    }

    static func openSettings() {
        let inputMonitoringSettings = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
        if let inputMonitoringSettings,
           NSWorkspace.shared.open(inputMonitoringSettings) {
            return
        }

        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )
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
