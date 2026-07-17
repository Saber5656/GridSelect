@testable import GridSelectCore
import XCTest

final class GridSelectStatusSnapshotTests: XCTestCase {
    func testMissingInputMonitoringIsIndependentAndActionable() {
        let snapshot = GridSelectStatusSnapshot(
            inputMonitoringStatus: .required,
            permissionStatus: .granted,
            shortcutStatus: .inactive(displayName: "Double-Shift"),
            selectionState: .idle
        )

        XCTAssertFalse(snapshot.isReady)
        XCTAssertEqual(snapshot.statusTitle, "Input Monitoring required")
        XCTAssertTrue(snapshot.statusDetail.contains("Privacy & Security > Input Monitoring"))
        XCTAssertTrue(snapshot.statusDetail.contains("recheck"))
    }

    func testMissingPermissionTakesPriorityOverInactiveShortcut() {
        let snapshot = GridSelectStatusSnapshot(
            inputMonitoringStatus: .granted,
            permissionStatus: .required,
            shortcutStatus: .inactive(displayName: "⌘⇧G"),
            selectionState: .idle
        )

        XCTAssertFalse(snapshot.isReady)
        XCTAssertEqual(snapshot.statusTitle, "Accessibility required")
        XCTAssertEqual(
            snapshot.statusDetail,
            "Open System Settings, then go to Privacy & Security > Accessibility and enable GridSelect, then recheck."
        )
    }

    func testGrantedPermissionAndActiveShortcutAreReady() {
        let snapshot = GridSelectStatusSnapshot(
            inputMonitoringStatus: .granted,
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

    func testActiveSelectionStatesAreNotReadyForAnotherActivation() {
        let rectangle = SelectionRectangle(
            displayID: 1,
            x: 10,
            y: 20,
            width: 30,
            height: 40
        )
        let activeStates: [SelectionModeState] = [
            .selecting,
            .dragging(rectangle),
            .confirmed(rectangle),
            .extracting(rectangle),
            .copying,
        ]

        for selectionState in activeStates {
            let snapshot = GridSelectStatusSnapshot(
                inputMonitoringStatus: .granted,
                permissionStatus: .granted,
                shortcutStatus: .active(displayName: "⌘⇧G"),
                selectionState: selectionState
            )

            XCTAssertFalse(snapshot.isReady, "Expected \(selectionState) not to be ready")
        }
    }

    func testSelectionLifecycleStatesHaveDistinctUserFacingStatus() {
        let base = GridSelectStatusSnapshot(
            inputMonitoringStatus: .granted,
            permissionStatus: .granted,
            shortcutStatus: .active(displayName: "Double-Shift"),
            selectionState: .idle
        )

        XCTAssertEqual(base.updating(selectionState: .selecting).statusTitle, "Grid mode armed")
        XCTAssertEqual(
            base.updating(
                selectionState: .dragging(
                    SelectionRectangle(displayID: 1, x: 0, y: 0, width: 10, height: 20)
                )
            ).statusTitle,
            "Adjusting selection"
        )
        XCTAssertEqual(
            base.updating(
                selectionState: .confirmed(
                    SelectionRectangle(displayID: 1, x: 0, y: 0, width: 10, height: 20)
                )
            ).statusTitle,
            "Selection frozen"
        )
    }

    func testInactiveShortcutIsNotPresentedAsReady() {
        let snapshot = GridSelectStatusSnapshot(
            inputMonitoringStatus: .granted,
            permissionStatus: .granted,
            shortcutStatus: .inactive(displayName: "⌘⇧G"),
            selectionState: .idle
        )

        XCTAssertFalse(snapshot.isReady)
        XCTAssertEqual(snapshot.statusTitle, "Shortcut not active")
        XCTAssertEqual(snapshot.statusDetail, "The shortcut ⌘⇧G is currently inactive.")
        XCTAssertEqual(snapshot.statusSymbolName, "exclamationmark.triangle.fill")
    }

    func testSelectionOutcomeOverridesReadinessSummary() {
        let ready = GridSelectStatusSnapshot(
            inputMonitoringStatus: .granted,
            permissionStatus: .granted,
            shortcutStatus: .active(displayName: "⌘⇧G"),
            selectionState: .completed
        )
        let copyFailure = GridSelectStatusSnapshot(
            inputMonitoringStatus: .granted,
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

    func testCopyingStatusExplainsPlainTextProgressAndCancellation() {
        let snapshot = GridSelectStatusSnapshot(
            inputMonitoringStatus: .granted,
            permissionStatus: .granted,
            shortcutStatus: .active(displayName: "Double-Shift"),
            selectionState: .copying
        )

        XCTAssertEqual(snapshot.statusTitle, "Copying selection")
        XCTAssertTrue(snapshot.statusDetail.contains("rectangular plain text"))
        XCTAssertTrue(snapshot.statusDetail.contains("Escape"))
    }

    func testShortcutRegistrationFailureHasRecoveryCopy() {
        let snapshot = GridSelectStatusSnapshot(
            inputMonitoringStatus: .granted,
            permissionStatus: .granted,
            shortcutStatus: .registrationFailed(displayName: "⌘⇧G"),
            selectionState: .idle
        )

        XCTAssertEqual(snapshot.statusTitle, "Shortcut unavailable")
        XCTAssertTrue(snapshot.statusDetail.contains("not available in this pre-alpha build"))
    }

    func testStatusCanBeUpdatedFromRuntimeAdaptersWithoutRebuildingUnrelatedState() {
        let initial = GridSelectStatusSnapshot(
            inputMonitoringStatus: .granted,
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

    func testGrantingPermissionClearsStalePermissionRequiredState() {
        let permissionRequired = GridSelectStatusSnapshot(
            inputMonitoringStatus: .granted,
            permissionStatus: .required,
            shortcutStatus: .active(displayName: "⌘⇧G"),
            selectionState: .permissionRequired
        )

        let granted = permissionRequired.updating(permissionStatus: .granted)

        XCTAssertEqual(granted.permissionStatus, .granted)
        XCTAssertEqual(granted.selectionState, .idle)
        XCTAssertTrue(granted.isReady)
        XCTAssertEqual(granted.statusTitle, "Ready to select")
    }

    func testUnrelatedUpdatePreservesPermissionRequiredState() {
        let permissionRequired = GridSelectStatusSnapshot(
            inputMonitoringStatus: .granted,
            permissionStatus: .granted,
            shortcutStatus: .inactive(displayName: "⌘⇧G"),
            selectionState: .permissionRequired
        )

        let shortcutActive = permissionRequired.updating(
            shortcutStatus: .active(displayName: "⌘⇧G")
        )

        XCTAssertEqual(shortcutActive.permissionStatus, .granted)
        XCTAssertEqual(shortcutActive.selectionState, .permissionRequired)
        XCTAssertFalse(shortcutActive.isReady)
        XCTAssertEqual(shortcutActive.statusTitle, "Accessibility required")
    }

    func testListenerDisabledHasActionableStatus() {
        let snapshot = GridSelectStatusSnapshot(
            inputMonitoringStatus: .granted,
            permissionStatus: .granted,
            shortcutStatus: .active(displayName: "Double-Shift"),
            selectionState: .failed(.listenerDisabled)
        )

        XCTAssertEqual(snapshot.statusTitle, "Grid listener disabled")
        XCTAssertTrue(snapshot.statusDetail.contains("Input Monitoring"))
    }

    func testListenerDisabledAfterRevocationShowsInputMonitoringRecovery() {
        let snapshot = GridSelectStatusSnapshot(
            inputMonitoringStatus: .required,
            permissionStatus: .granted,
            shortcutStatus: .inactive(displayName: "Double-Shift"),
            selectionState: .failed(.listenerDisabled)
        )

        XCTAssertEqual(snapshot.statusTitle, "Input Monitoring required")
        XCTAssertEqual(snapshot.statusDetail, GridSelectStatusSnapshot.inputMonitoringGuidance)
    }
}
