@testable import GridSelectCore
import XCTest

final class GridSelectStatusSnapshotTests: XCTestCase {
    func testMissingPermissionTakesPriorityOverInactiveShortcut() {
        let snapshot = GridSelectStatusSnapshot(
            permissionStatus: .required,
            shortcutStatus: .inactive(displayName: "⌘⇧G"),
            selectionState: .idle
        )

        XCTAssertFalse(snapshot.isReady)
        XCTAssertEqual(snapshot.statusTitle, "Accessibility required")
        XCTAssertEqual(
            snapshot.statusDetail,
            "Open System Settings, then go to Privacy & Security > Accessibility and enable GridSelect."
        )
    }

    func testGrantedPermissionAndActiveShortcutAreReady() {
        let snapshot = GridSelectStatusSnapshot(
            permissionStatus: .granted,
            shortcutStatus: .active(displayName: "⌘⇧G"),
            selectionState: .idle
        )

        XCTAssertTrue(snapshot.isReady)
        XCTAssertEqual(snapshot.statusTitle, "Ready to select")
        XCTAssertEqual(
            snapshot.statusDetail,
            "Press ⌘⇧G to start a rectangular selection."
        )
    }

    func testInactiveShortcutIsNotPresentedAsReady() {
        let snapshot = GridSelectStatusSnapshot(
            permissionStatus: .granted,
            shortcutStatus: .inactive(displayName: "⌘⇧G"),
            selectionState: .idle
        )

        XCTAssertFalse(snapshot.isReady)
        XCTAssertEqual(snapshot.statusTitle, "Shortcut not active")
        XCTAssertTrue(snapshot.statusDetail.contains("runtime registration is not connected yet"))
        XCTAssertEqual(snapshot.statusSymbolName, "exclamationmark.triangle.fill")
    }

    func testSelectionOutcomeOverridesReadinessSummary() {
        let ready = GridSelectStatusSnapshot(
            permissionStatus: .granted,
            shortcutStatus: .active(displayName: "⌘⇧G"),
            selectionState: .completed
        )
        let copyFailure = GridSelectStatusSnapshot(
            permissionStatus: .granted,
            shortcutStatus: .active(displayName: "⌘⇧G"),
            selectionState: .failed(.clipboardWriteFailed)
        )

        XCTAssertEqual(ready.statusTitle, "Copied to clipboard")
        XCTAssertEqual(ready.statusSymbolName, "checkmark.circle.fill")
        XCTAssertEqual(copyFailure.statusTitle, "Copy failed")
        XCTAssertEqual(copyFailure.statusSymbolName, "exclamationmark.triangle.fill")
        XCTAssertEqual(
            copyFailure.statusDetail,
            "GridSelect could not write the selected text to the clipboard."
        )
    }

    func testShortcutRegistrationFailureHasRecoveryCopy() {
        let snapshot = GridSelectStatusSnapshot(
            permissionStatus: .granted,
            shortcutStatus: .registrationFailed(displayName: "⌘⇧G"),
            selectionState: .idle
        )

        XCTAssertEqual(snapshot.statusTitle, "Shortcut unavailable")
        XCTAssertTrue(snapshot.statusDetail.contains("not available in this pre-alpha build"))
    }

    func testStatusCanBeUpdatedFromRuntimeAdaptersWithoutRebuildingUnrelatedState() {
        let initial = GridSelectStatusSnapshot(
            permissionStatus: .required,
            shortcutStatus: .inactive(displayName: "⌘⇧G"),
            selectionState: .idle
        )

        let permissionGranted = initial.updating(permissionStatus: .granted)
        let shortcutActive = permissionGranted.updating(
            shortcutStatus: .active(displayName: "⌘⇧G")
        )
        let completed = shortcutActive.updating(selectionState: .completed)

        XCTAssertEqual(permissionGranted.shortcutStatus, initial.shortcutStatus)
        XCTAssertEqual(shortcutActive.selectionState, .idle)
        XCTAssertTrue(shortcutActive.isReady)
        XCTAssertEqual(completed.statusTitle, "Copied to clipboard")
        XCTAssertEqual(completed.statusSymbolName, "checkmark.circle.fill")
    }
}
