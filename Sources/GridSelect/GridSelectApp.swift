import AppKit
import GridSelectCore
import SwiftUI

@main
struct GridSelectApp: App {
    @NSApplicationDelegateAdaptor(GridSelectAppDelegate.self) private var appDelegate
    private let runtime = GridSelectRuntime()

    var body: some Scene {
        MenuBarExtra {
            GridSelectMenuView(
                controller: appDelegate.controller,
                statusModel: appDelegate.controller.statusModel
            )
        } label: {
            GridSelectMenuBarLabel(
                permissionSetupPresenter: appDelegate.permissionSetupPresenter
            )
        }

        Settings {
            GridSelectSettingsView(
                runtime: runtime,
                controller: appDelegate.controller,
                statusModel: appDelegate.controller.statusModel
            )
        }
    }
}

private struct GridSelectMenuBarLabel: View {
    let permissionSetupPresenter: MacOSPermissionSetupPresenter

    @ViewBuilder
    var body: some View {
        if #available(macOS 14.0, *) {
            GridSelectModernMenuBarLabel(
                permissionSetupPresenter: permissionSetupPresenter
            )
        } else {
            Image(systemName: "rectangle.inset.filled")
                .accessibilityLabel("GridSelect")
        }
    }
}

@available(macOS 14.0, *)
private struct GridSelectModernMenuBarLabel: View {
    @Environment(\.openSettings) private var openSettings
    let permissionSetupPresenter: MacOSPermissionSetupPresenter

    var body: some View {
        Image(systemName: "rectangle.inset.filled")
            .accessibilityLabel("GridSelect")
            .onAppear {
                permissionSetupPresenter.installOpenSettingsAction {
                    openSettings()
                }
            }
    }
}

private struct GridSelectMenuView: View {
    let controller: GridSelectApplicationController
    @ObservedObject var statusModel: GridSelectStatusModel

    var body: some View {
        Text(statusModel.snapshot.statusTitle)
            .font(.headline)
        Text(shortcutSummary)
            .font(.caption)
        Divider()
        Button("Start Selection") {
            controller.activateSelection()
        }
        .disabled(statusModel.snapshot.selectionState.isActive)
        if statusModel.snapshot.selectionState.isActive {
            Button("Cancel Selection") {
                controller.cancelSelection()
            }
        }
        Divider()
        if statusModel.snapshot.inputMonitoringStatus == .required {
            Button("Open Input Monitoring Settings") {
                statusModel.openInputMonitoringSettings()
            }
        }
        Button("Recheck Input Monitoring") {
            controller.recheckInputMonitoring()
        }
        if statusModel.snapshot.permissionStatus == .required {
            Button("Open Accessibility Settings") {
                statusModel.openAccessibilitySettings()
            }
        }
        Button("Recheck Accessibility") {
            statusModel.recheckPermission()
        }
        if #available(macOS 14.0, *) {
            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",", modifiers: .command)
        } else {
            Button("Settings…") {
                NSApplication.shared.sendAction(
                    Selector(("showSettingsWindow:")),
                    to: nil,
                    from: nil
                )
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var shortcutSummary: String {
        switch statusModel.snapshot.shortcutStatus {
        case let .active(displayName):
            return "Active shortcut: \(displayName)"
        case let .inactive(displayName):
            return "Shortcut not active: \(displayName)"
        case let .registrationFailed(displayName):
            return "Shortcut unavailable: \(displayName)"
        }
    }
}

private struct GridSelectSettingsView: View {
    let runtime: GridSelectRuntime
    let controller: GridSelectApplicationController
    @ObservedObject var statusModel: GridSelectStatusModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
            Text(runtime.name)
                .font(.title2)
            Label(
                statusModel.snapshot.statusTitle,
                systemImage: statusModel.snapshot.statusSymbolName
            )
            .font(.headline)

            Text(statusModel.snapshot.statusDetail)
                .foregroundStyle(.secondary)

            Divider()

            LabeledContent(
                "Activation gesture"
            ) {
                Text(shortcutSettingsValue)
                    .monospaced()
            }

            LabeledContent("Input Monitoring") {
                Text(
                    statusModel.snapshot.inputMonitoringStatus == .granted
                        ? "Granted"
                        : "Required"
                )
            }

            if statusModel.snapshot.inputMonitoringStatus == .required {
                Text(GridSelectStatusSnapshot.inputMonitoringGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Request Input Monitoring Access") {
                    controller.requestInputMonitoringAccess()
                }
                Button("Open Input Monitoring Settings") {
                    statusModel.openInputMonitoringSettings()
                }
            }

            Button("Recheck Input Monitoring") {
                controller.recheckInputMonitoring()
            }

            LabeledContent("Accessibility") {
                Text(
                    statusModel.snapshot.permissionStatus == .granted
                        ? "Granted"
                        : "Required"
                )
            }

            if statusModel.snapshot.permissionStatus == .required {
                Text("GridSelect uses Accessibility only after you start a selection, to read text positions in the selected app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Request Accessibility Access") {
                    statusModel.requestAccessibilityAccess()
                }
                Button("Open Accessibility Settings") {
                    statusModel.openAccessibilitySettings()
                }
            }

            Button("Recheck Accessibility") {
                statusModel.recheckPermission()
            }

            Divider()

            Group {
                Text("Double-Shift to enter Grid mode.")
                    .font(.headline)
                Text("GridSelect normally passes keyboard input unchanged. During the brief startup handoff it consumes only Arrow, Command-C, or Escape; it stores no typed characters, and typed characters plus Shift release pass through. Later Grid commands stay inside the overlay.")
                Text("Keyboard: start from the zero-area text caret. Left/Right changes the column extent one character at a time; Up/Down adds adjacent-row cursors, VS Code-style.")
                Text("Mouse: the first click is the anchor. Drag across the same character-cell grid. If keyboard caret anchoring is unsupported, use this mouse path.")
                Text("Release Shift or the mouse to freeze the selection. Command-C copies a nonzero-width rectangle as plain text; Escape cancels without copying.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Start Selection") {
                controller.activateSelection()
            }
            .disabled(statusModel.snapshot.selectionState.isActive)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 420)
        .frame(minHeight: 360, idealHeight: 620, maxHeight: 720)
    }

    private var shortcutSettingsValue: String {
        switch statusModel.snapshot.shortcutStatus {
        case let .active(displayName):
            return displayName
        case let .inactive(displayName):
            return "\(displayName) (not active)"
        case let .registrationFailed(displayName):
            return "\(displayName) (registration failed)"
        }
    }
}
