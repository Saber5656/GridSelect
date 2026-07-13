import AppKit
import GridSelectCore
import SwiftUI

@main
struct GridSelectApp: App {
    private let runtime = GridSelectRuntime()
    @StateObject private var statusModel = GridSelectStatusModel()

    var body: some Scene {
        MenuBarExtra("GridSelect", systemImage: "rectangle.inset.filled") {
            GridSelectMenuView(statusModel: statusModel)
        }

        Settings {
            GridSelectSettingsView(runtime: runtime, statusModel: statusModel)
        }
    }
}

private struct GridSelectMenuView: View {
    @ObservedObject var statusModel: GridSelectStatusModel

    var body: some View {
        Text(statusModel.snapshot.statusTitle)
            .font(.headline)
        Text(shortcutSummary)
            .font(.caption)
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
        if statusModel.snapshot.shortcutStatus.isActive {
            return "Active shortcut: \(statusModel.snapshot.shortcutStatus.displayName)"
        }
        return "Planned shortcut: \(statusModel.snapshot.shortcutStatus.displayName) (not active)"
    }
}

private struct GridSelectSettingsView: View {
    let runtime: GridSelectRuntime
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
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
    }

    private var shortcutSettingsValue: String {
        if statusModel.snapshot.shortcutStatus.isActive {
            return statusModel.snapshot.shortcutStatus.displayName
        }
        return "\(statusModel.snapshot.shortcutStatus.displayName) (not active)"
    }
}
