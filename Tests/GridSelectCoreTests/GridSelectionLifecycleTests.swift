import XCTest
@testable import GridSelectCore

final class GridSelectionLifecycleTests: XCTestCase {
    func testKeyboardStartsAtZeroAreaAndMovesHalfOpenBoundaries() {
        var lifecycle = GridSelectionLifecycle()
        let activation = GridActivation(generation: 7)
        XCTAssertTrue(lifecycle.begin(activation))

        XCTAssertEqual(
            lifecycle.bindKeyboardAnchor(GridBoundary(row: 4, column: 10)),
            .selectionChanged(
                GridIndexSelection(anchor: GridBoundary(row: 4, column: 10))
            )
        )
        XCTAssertEqual(currentSelection(lifecycle).rowRange, 4..<5)
        XCTAssertEqual(currentSelection(lifecycle).columnRange, 10..<10)

        _ = lifecycle.moveKeyboardFocus(.right)
        _ = lifecycle.moveKeyboardFocus(.down)
        let selection = currentSelection(lifecycle)
        XCTAssertEqual(selection.rowRange, 4..<6)
        XCTAssertEqual(selection.columnRange, 10..<11)
    }

    func testCrossingAnchorNormalizesAndRepeatMovesOneBoundary() {
        var lifecycle = adjustingLifecycle(anchor: GridBoundary(row: 2, column: 2))

        _ = lifecycle.moveKeyboardFocus(.right)
        _ = lifecycle.moveKeyboardFocus(.right)
        XCTAssertEqual(currentSelection(lifecycle).columnRange, 2..<4)
        _ = lifecycle.moveKeyboardFocus(.left)
        _ = lifecycle.moveKeyboardFocus(.left)
        XCTAssertEqual(currentSelection(lifecycle).columnRange, 2..<2)
        _ = lifecycle.moveKeyboardFocus(.left)
        XCTAssertEqual(currentSelection(lifecycle).columnRange, 1..<2)
    }

    func testFreezeRetainsSelectionAndIgnoresLaterArrow() {
        var lifecycle = adjustingLifecycle(anchor: GridBoundary(row: 0, column: 0))
        _ = lifecycle.moveKeyboardFocus(.right)

        let frozen = lifecycle.freeze()
        let stateBeforeArrow = lifecycle.state
        XCTAssertEqual(
            frozen,
            .selectionFrozen(
                GridIndexSelection(
                    anchor: GridBoundary(row: 0, column: 0),
                    focus: GridBoundary(row: 0, column: 1)
                )
            )
        )
        XCTAssertNil(lifecycle.moveKeyboardFocus(.right))
        XCTAssertEqual(lifecycle.state, stateBeforeArrow)
    }

    func testZeroWidthCopyKeepsSelectionAndMouseMayReanchor() {
        var lifecycle = adjustingLifecycle(anchor: GridBoundary(row: 1, column: 3))
        _ = lifecycle.freeze()
        let frozen = lifecycle.state

        XCTAssertEqual(lifecycle.requestCopy(), .selectAtLeastOneColumn)
        XCTAssertEqual(lifecycle.state, frozen)
        XCTAssertEqual(
            lifecycle.beginMouseSelection(at: GridBoundary(row: 5, column: 8)),
            .selectionChanged(
                GridIndexSelection(anchor: GridBoundary(row: 5, column: 8))
            )
        )
    }

    func testCopyIsSingleFlightAndStaleCompletionIsRejected() throws {
        var lifecycle = adjustingLifecycle(anchor: GridBoundary(row: 0, column: 0))
        _ = lifecycle.moveKeyboardFocus(.right)
        _ = lifecycle.freeze()
        let effect = lifecycle.requestCopy()
        guard case let .copyStarted(authorization) = effect else {
            return XCTFail("Expected a copy authorization")
        }

        XCTAssertEqual(lifecycle.requestCopy(), .copyRequestConsumed)
        let stale = GridCopyAuthorization(
            activation: authorization.activation,
            sequence: authorization.sequence + 1,
            selection: authorization.selection
        )
        XCTAssertEqual(
            lifecycle.finishCopy(stale, succeeded: true),
            .staleResultDiscarded
        )
        XCTAssertEqual(lifecycle.state, .copying(authorization))
        XCTAssertEqual(lifecycle.finishCopy(authorization, succeeded: true), .completed)
        XCTAssertEqual(lifecycle.state, .completed(authorization.activation))
    }

    func testOrderedHandoffFreezesBeforeLaterArrow() {
        var lifecycle = adjustingLifecycle(anchor: GridBoundary(row: 0, column: 0))

        let effects = lifecycle.applyHandoffCommands([
            .move(.right),
            .freeze,
            .move(.right),
        ])

        XCTAssertEqual(effects.count, 2)
        guard case let .selected(_, selection) = lifecycle.state else {
            return XCTFail("Expected frozen selection")
        }
        XCTAssertEqual(selection.columnRange, 0..<1)
    }

    func testMouseOneColumnAndInclusiveEndpointRowsFreeze() {
        var lifecycle = GridSelectionLifecycle()
        XCTAssertTrue(lifecycle.begin(GridActivation(generation: 1)))
        _ = lifecycle.beginMouseSelection(at: GridBoundary(row: 2, column: 4))
        _ = lifecycle.moveMouseFocus(to: GridBoundary(row: 4, column: 5))
        _ = lifecycle.freeze()

        guard case let .selected(_, selection) = lifecycle.state else {
            return XCTFail("Expected mouse selection")
        }
        XCTAssertEqual(selection.rowRange, 2..<5)
        XCTAssertEqual(selection.columnRange, 4..<5)
    }

    func testVerticalCrossingAndRowZeroClamp() {
        var lifecycle = adjustingLifecycle(anchor: GridBoundary(row: 1, column: 3))
        _ = lifecycle.moveKeyboardFocus(.up)
        _ = lifecycle.moveKeyboardFocus(.up)
        _ = lifecycle.moveKeyboardFocus(.up)
        XCTAssertEqual(currentSelection(lifecycle).rowRange, 0..<2)
        _ = lifecycle.moveKeyboardFocus(.down)
        _ = lifecycle.moveKeyboardFocus(.down)
        XCTAssertEqual(currentSelection(lifecycle).rowRange, 1..<2)
        _ = lifecycle.moveKeyboardFocus(.down)
        XCTAssertEqual(currentSelection(lifecycle).rowRange, 1..<3)
    }

    func testFailedCopyIsTerminalAndCancelRejectsStaleCompletion() {
        var failed = adjustingLifecycle(anchor: GridBoundary(row: 0, column: 0))
        _ = failed.moveKeyboardFocus(.right)
        _ = failed.freeze()
        guard case let .copyStarted(failedAuthorization) = failed.requestCopy() else {
            return XCTFail("Expected copy")
        }
        XCTAssertEqual(failed.finishCopy(failedAuthorization, succeeded: false), .failed)
        XCTAssertEqual(failed.state, .failed(failedAuthorization.activation))
        XCTAssertNil(failed.cancel())

        var cancelled = adjustingLifecycle(anchor: GridBoundary(row: 0, column: 0))
        _ = cancelled.moveKeyboardFocus(.right)
        _ = cancelled.freeze()
        guard case let .copyStarted(cancelledAuthorization) = cancelled.requestCopy() else {
            return XCTFail("Expected copy")
        }
        XCTAssertEqual(cancelled.cancel(), .cancelled)
        XCTAssertEqual(
            cancelled.finishCopy(cancelledAuthorization, succeeded: true),
            .staleResultDiscarded
        )
        XCTAssertEqual(cancelled.state, .cancelled(cancelledAuthorization.activation))
    }

    private func adjustingLifecycle(anchor: GridBoundary) -> GridSelectionLifecycle {
        var lifecycle = GridSelectionLifecycle()
        XCTAssertTrue(lifecycle.begin(GridActivation(generation: 1)))
        _ = lifecycle.bindKeyboardAnchor(anchor)
        return lifecycle
    }

    private func currentSelection(_ lifecycle: GridSelectionLifecycle) -> GridIndexSelection {
        switch lifecycle.state {
        case let .adjusting(_, selection), let .selected(_, selection):
            return selection
        default:
            XCTFail("Expected a selection state")
            return GridIndexSelection(anchor: GridBoundary(row: 0, column: 0))
        }
    }
}
