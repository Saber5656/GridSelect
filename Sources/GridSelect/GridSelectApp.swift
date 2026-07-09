import AppKit
import GridSelectCore
import SwiftUI

@main
struct GridSelectApp: App {
    private let runtime = GridSelectRuntime()

    var body: some Scene {
        MenuBarExtra("GridSelect", systemImage: "rectangle.inset.filled") {
            Text(runtime.statusText)
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }

        Settings {
            GridSelectSettingsView(runtime: runtime)
        }
    }
}

private struct GridSelectSettingsView: View {
    let runtime: GridSelectRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(runtime.name)
                .font(.title2)
            Text(runtime.statusText)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 320, alignment: .leading)
    }
}
