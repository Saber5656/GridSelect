import AppKit
import GridSelectCore
import SwiftUI

@main
struct GridSelectApp: App {
    @NSApplicationDelegateAdaptor(GridSelectAppDelegate.self) private var appDelegate
    private let runtime = GridSelectRuntime()

    var body: some Scene {
        MenuBarExtra("GridSelect", systemImage: "rectangle.inset.filled") {
            GridSelectMenuView(
                controller: appDelegate.controller,
                statusModel: appDelegate.controller.statusModel
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
        if statusModel.snapshot.permissionStatus == .required {
            Button("Open Accessibility Settings") {
                statusModel.openAccessibilitySettings()
            }
        }
        Button("Recheck Accessibility") {
            statusModel.recheckPermission()
        }
        Button("Settings…") {
            NSApplication.shared.sendAction(
                Selector(("showSettingsWindow:")),
                to: nil,
                from: nil
            )
        }
        .keyboardShortcut(",", modifiers: .command)
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
                statusModel.snapshot.shortcutStatus.isActive
                    ? "Active shortcut"
                    : "Planned shortcut"
            ) {
                Text(shortcutSettingsValue)
                    .monospaced()
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

            Button("Start Selection") {
                controller.activateSelection()
            }
            .disabled(statusModel.snapshot.selectionState.isActive)
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
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
