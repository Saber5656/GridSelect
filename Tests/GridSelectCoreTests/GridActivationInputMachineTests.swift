import XCTest
@testable import GridSelectCore

final class GridActivationInputMachineTests: XCTestCase {
    func testOnlyDownUpDownWithinSystemIntervalActivates() {
        var machine = GridActivationInputMachine(doubleClickInterval: 0.4)

        XCTAssertEqual(machine.handleShiftChange(isDown: true, timestamp: 1), .passThrough)
        XCTAssertEqual(machine.handleShiftChange(isDown: false, timestamp: 1.05), .passThrough)
        let result = machine.handleShiftChange(isDown: true, timestamp: 1.3)

        XCTAssertEqual(result.delivery, .passThrough)
        XCTAssertEqual(result.effect, .activated(GridActivation(generation: 1)))
        XCTAssertTrue(machine.requiresGuardedKeyClassification)
    }

    func testSlowSecondShiftStartsANewCandidateInsteadOfActivating() {
        var machine = GridActivationInputMachine(doubleClickInterval: 0.2)

        _ = machine.handleShiftChange(isDown: true, timestamp: 1)
        _ = machine.handleShiftChange(isDown: false, timestamp: 1.05)
        XCTAssertEqual(
            machine.handleShiftChange(isDown: true, timestamp: 1.3),
            .passThrough
        )
        _ = machine.handleShiftChange(isDown: false, timestamp: 1.35)

        let activation = machine.handleShiftChange(isDown: true, timestamp: 1.4)
        XCTAssertEqual(activation.effect, .activated(GridActivation(generation: 1)))
    }

    func testOrdinaryKeyInvalidatesPendingGestureWithoutClassification() {
        var machine = GridActivationInputMachine(doubleClickInterval: 0.4)
        _ = machine.handleShiftChange(isDown: true, timestamp: 1)
        _ = machine.handleShiftChange(isDown: false, timestamp: 1.05)

        XCTAssertEqual(machine.handleUnclassifiedKeyDown(), .passThrough)
        XCTAssertEqual(machine.handleShiftChange(isDown: true, timestamp: 1.1), .passThrough)
        XCTAssertFalse(machine.requiresGuardedKeyClassification)
    }

    func testHandoffPreservesArrowFreezeArrowOrder() {
        var machine = activatedMachine()
        let activation = try! XCTUnwrap(machine.activeHandoff)

        XCTAssertEqual(
            machine.handleGuardedKeyDown(.arrow(.right), timestamp: 1.11).delivery,
            .consume
        )
        XCTAssertEqual(
            machine.handleShiftChange(isDown: false, timestamp: 1.12).delivery,
            .passThrough
        )
        XCTAssertEqual(
            machine.handleGuardedKeyDown(.arrow(.right), timestamp: 1.13).delivery,
            .consume
        )

        XCTAssertEqual(
            machine.completeHandoff(for: activation, timestamp: 1.2),
            [.move(.right), .freeze, .move(.right)]
        )
    }

    func testEveryRepeatCountsAndThirtyThirdCommandCancelsBeforeAppend() {
        var machine = activatedMachine()
        let activation = try! XCTUnwrap(machine.activeHandoff)

        for index in 0..<GridActivationInputMachine.handoffQueueCapacity {
            let result = machine.handleGuardedKeyDown(
                .arrow(.down),
                timestamp: 1.11 + (Double(index) * 0.001)
            )
            XCTAssertEqual(result, .consume)
        }

        let overflow = machine.handleGuardedKeyDown(.commandC, timestamp: 1.2)
        XCTAssertEqual(overflow.delivery, .consume)
        XCTAssertEqual(
            overflow.effect,
            .handoffCancelled(activation, .queueOverflow)
        )
        XCTAssertNil(machine.completeHandoff(for: activation, timestamp: 1.2))
    }

    func testFreezeCountsAsEntryAndNextSemanticOverflows() {
        var machine = activatedMachine()
        let activation = try! XCTUnwrap(machine.activeHandoff)
        for index in 0..<31 {
            XCTAssertEqual(
                machine.handleGuardedKeyDown(
                    .arrow(.down),
                    timestamp: 1.11 + (Double(index) * 0.001)
                ),
                .consume
            )
        }
        XCTAssertEqual(
            machine.handleShiftChange(isDown: false, timestamp: 1.15),
            .passThrough
        )

        let overflow = machine.handleGuardedKeyDown(.commandC, timestamp: 1.16)
        XCTAssertEqual(overflow.delivery, .consume)
        XCTAssertEqual(overflow.effect, .handoffCancelled(activation, .queueOverflow))
    }

    func testOverflowingFreezeStillPassesShiftReleaseAndCancelsBeforeAppend() {
        var machine = activatedMachine()
        let activation = try! XCTUnwrap(machine.activeHandoff)
        for index in 0..<32 {
            _ = machine.handleGuardedKeyDown(
                .arrow(.down),
                timestamp: 1.11 + (Double(index) * 0.001)
            )
        }

        let overflow = machine.handleShiftChange(isDown: false, timestamp: 1.16)
        XCTAssertEqual(overflow.delivery, .passThrough)
        XCTAssertEqual(overflow.effect, .handoffCancelled(activation, .queueOverflow))
    }

    func testOrdinaryKeyDuringHandoffCancelsAndPassesThrough() {
        var machine = activatedMachine()
        let activation = try! XCTUnwrap(machine.activeHandoff)

        let result = machine.handleGuardedKeyDown(.other, timestamp: 1.11)

        XCTAssertEqual(result.delivery, .passThrough)
        XCTAssertEqual(result.effect, .handoffCancelled(activation, .ordinaryKey))
    }

    func testExpiredGuardPassesCurrentGridKeyAndRejectsStaleCompletion() {
        var machine = activatedMachine()
        let activation = try! XCTUnwrap(machine.activeHandoff)

        let result = machine.handleGuardedKeyDown(.arrow(.left), timestamp: 1.61)

        XCTAssertEqual(result.delivery, .passThrough)
        XCTAssertEqual(result.effect, .handoffCancelled(activation, .timedOut))
        XCTAssertNil(machine.completeHandoff(for: activation, timestamp: 1.61))
    }

    func testExpiredGuardPassesOrdinaryKeyWhileCancellingHandoff() {
        var machine = activatedMachine()
        let activation = try! XCTUnwrap(machine.activeHandoff)

        let result = machine.handleGuardedKeyDown(.other, timestamp: 1.61)

        XCTAssertEqual(result.delivery, .passThrough)
        XCTAssertEqual(result.effect, .handoffCancelled(activation, .timedOut))
        XCTAssertNil(machine.completeHandoff(for: activation, timestamp: 1.61))
    }

    func testExplicitExpiryCancelsWithoutAnotherInputEvent() {
        var machine = activatedMachine()
        let activation = try! XCTUnwrap(machine.activeHandoff)

        XCTAssertEqual(
            machine.expireHandoff(for: activation, timestamp: 1.61),
            .handoffCancelled(activation, .timedOut)
        )
        XCTAssertNil(machine.completeHandoff(for: activation, timestamp: 1.61))
    }

    func testFallbackCompletionDrainsCommandsAtDeadline() {
        var machine = activatedMachine()
        let activation = try! XCTUnwrap(machine.activeHandoff)
        _ = machine.handleGuardedKeyDown(.arrow(.right), timestamp: 1.11)

        XCTAssertEqual(
            machine.completeHandoffAtDeadline(for: activation),
            [.move(.right)]
        )
        XCTAssertNil(machine.activeHandoff)
    }

    func testFreezeBeforeArrowIsDistinctFromArrowBeforeFreeze() {
        var freezeFirst = activatedMachine()
        let freezeActivation = try! XCTUnwrap(freezeFirst.activeHandoff)
        _ = freezeFirst.handleShiftChange(isDown: false, timestamp: 1.11)
        _ = freezeFirst.handleGuardedKeyDown(.arrow(.right), timestamp: 1.12)

        var arrowFirst = activatedMachine()
        let arrowActivation = try! XCTUnwrap(arrowFirst.activeHandoff)
        _ = arrowFirst.handleGuardedKeyDown(.arrow(.right), timestamp: 1.11)
        _ = arrowFirst.handleShiftChange(isDown: false, timestamp: 1.12)

        XCTAssertEqual(
            freezeFirst.completeHandoff(for: freezeActivation, timestamp: 1.2),
            [.freeze, .move(.right)]
        )
        XCTAssertEqual(
            arrowFirst.completeHandoff(for: arrowActivation, timestamp: 1.2),
            [.move(.right), .freeze]
        )
    }

    func testStaleGenerationCannotDrainNewHandoff() {
        var machine = activatedMachine()
        let first = try! XCTUnwrap(machine.activeHandoff)
        _ = machine.cancelHandoff(for: first, reason: .setupFailed)
        _ = machine.handleShiftChange(isDown: false, timestamp: 2)
        _ = machine.handleShiftChange(isDown: true, timestamp: 2.1)
        _ = machine.handleShiftChange(isDown: false, timestamp: 2.15)
        _ = machine.handleShiftChange(isDown: true, timestamp: 2.2)
        let second = try! XCTUnwrap(machine.activeHandoff)

        XCTAssertNotEqual(first, second)
        XCTAssertNil(machine.completeHandoff(for: first, timestamp: 2.3))
        XCTAssertEqual(machine.completeHandoff(for: second, timestamp: 2.3), [])
    }

    private func activatedMachine() -> GridActivationInputMachine {
        var machine = GridActivationInputMachine(doubleClickInterval: 0.4)
        _ = machine.handleShiftChange(isDown: true, timestamp: 1)
        _ = machine.handleShiftChange(isDown: false, timestamp: 1.05)
        _ = machine.handleShiftChange(isDown: true, timestamp: 1.1)
        return machine
    }
}
