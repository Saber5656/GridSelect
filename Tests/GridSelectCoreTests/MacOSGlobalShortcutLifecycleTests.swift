@testable import GridSelect
import XCTest

@MainActor
final class MacOSGlobalShortcutLifecycleTests: XCTestCase {
    func testEnabledContextDeliversActivation() async {
        var activationCount = 0
        let context = MacOSHotKeyCallbackContext {
            activationCount += 1
        }
        context.enable()

        context.deliverIfEnabled()
        await Task.yield()

        XCTAssertEqual(activationCount, 1)
    }

    func testDisabledContextSuppressesQueuedActivation() async {
        var activationCount = 0
        let context = MacOSHotKeyCallbackContext {
            activationCount += 1
        }
        context.enable()

        context.deliverIfEnabled()
        context.disable()
        context.disable()
        await Task.yield()

        XCTAssertEqual(activationCount, 0)
    }

    func testMultipleUnregisterCallsAreSafeWithoutRegistration() {
        let shortcut = MacOSGlobalShortcut()

        shortcut.unregister()
        shortcut.unregister()
    }
}
