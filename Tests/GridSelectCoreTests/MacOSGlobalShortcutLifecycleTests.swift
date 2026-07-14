@testable import GridSelect
import CoreGraphics
import GridSelectCore
import XCTest

@MainActor
final class MacOSGlobalShortcutLifecycleTests: XCTestCase {
    func testEnabledContextDeliversActivation() throws {
        let effects = EffectCollector()
        let context = MacOSGridEventTapContext(doubleClickInterval: 1) { effect in
            effects.append(effect)
        }
        context.enable()

        XCTAssertTrue(context.process(type: .flagsChanged, event: try shiftEvent(isDown: true)))
        XCTAssertTrue(context.process(type: .flagsChanged, event: try shiftEvent(isDown: false)))
        XCTAssertTrue(context.process(type: .flagsChanged, event: try shiftEvent(isDown: true)))

        XCTAssertEqual(effects.values, [.activated(GridActivation(generation: 1))])
    }

    func testDisabledContextSuppressesActivation() throws {
        let effects = EffectCollector()
        let context = MacOSGridEventTapContext(doubleClickInterval: 1) { effect in
            effects.append(effect)
        }
        context.enable()
        context.disable()
        context.disable()

        XCTAssertTrue(context.process(type: .flagsChanged, event: try shiftEvent(isDown: true)))
        XCTAssertTrue(context.process(type: .flagsChanged, event: try shiftEvent(isDown: false)))
        XCTAssertTrue(context.process(type: .flagsChanged, event: try shiftEvent(isDown: true)))

        XCTAssertEqual(effects.values, [.listenerDisabled(nil)])
    }

    func testMultipleUnregisterCallsAreSafeWithoutRegistration() {
        let shortcut = MacOSGlobalShortcut()

        shortcut.unregister()
        shortcut.unregister()
    }

    func testGuardClassifiesAndConsumesOnlyGridCommands() throws {
        let effects = EffectCollector()
        let context = MacOSGridEventTapContext(doubleClickInterval: 1) {
            effects.append($0)
        }
        context.enable()
        try activate(context)

        XCTAssertFalse(context.process(type: .keyDown, event: try keyEvent(code: 124)))
        XCTAssertFalse(
            context.process(
                type: .keyDown,
                event: try keyEvent(code: 8, flags: .maskCommand)
            )
        )
        XCTAssertFalse(context.process(type: .keyDown, event: try keyEvent(code: 53)))
        XCTAssertEqual(
            context.completeHandoff(
                for: GridActivation(generation: 1),
                timestamp: ProcessInfo.processInfo.systemUptime
            ),
            [.move(.right), .copyRequested, .cancelRequested]
        )
    }

    func testConsumedKeyDownAlsoConsumesMatchingKeyUpAfterHandoff() throws {
        let context = MacOSGridEventTapContext(doubleClickInterval: 1) { _ in }
        context.enable()
        try activate(context)
        XCTAssertFalse(context.process(type: .keyDown, event: try keyEvent(code: 124)))
        XCTAssertNotNil(
            context.completeHandoff(
                for: GridActivation(generation: 1),
                timestamp: ProcessInfo.processInfo.systemUptime
            )
        )

        XCTAssertFalse(context.process(type: .keyUp, event: try keyEvent(code: 124)))
        XCTAssertTrue(context.process(type: .keyUp, event: try keyEvent(code: 125)))
    }

    func testKeyUpPassesWhenThereIsNoSuppressionTail() throws {
        let context = MacOSGridEventTapContext(doubleClickInterval: 1) { _ in }
        context.enable()

        XCTAssertTrue(context.process(type: .keyUp, event: try keyEvent(code: 124)))
    }

    func testMatchingKeyUpSuppressionTailExpiresAfterBoundedInterval() throws {
        let context = MacOSGridEventTapContext(doubleClickInterval: 1) { _ in }
        context.enable()
        try activate(context)
        let keyDownTimestamp = ProcessInfo.processInfo.systemUptime
        XCTAssertFalse(
            context.process(
                type: .keyDown,
                event: try keyEvent(code: 124),
                timestamp: keyDownTimestamp
            )
        )

        XCTAssertTrue(
            context.process(
                type: .keyUp,
                event: try keyEvent(code: 124),
                timestamp: keyDownTimestamp
                    + MacOSGridEventTapContext.matchingKeyUpSuppressionTimeout
                    + 0.001
            )
        )
    }

    func testOrdinaryKeyPassesThroughAndCancelsGuard() throws {
        let effects = EffectCollector()
        let context = MacOSGridEventTapContext(doubleClickInterval: 1) {
            effects.append($0)
        }
        context.enable()
        try activate(context)

        XCTAssertTrue(context.process(type: .keyDown, event: try keyEvent(code: 0)))
        XCTAssertEqual(
            effects.values.last,
            .handoffCancelled(GridActivation(generation: 1), .ordinaryKey)
        )
    }

    func testShiftReleasePassesAndTapDisablementFailsClosed() throws {
        let effects = EffectCollector()
        let context = MacOSGridEventTapContext(doubleClickInterval: 1) {
            effects.append($0)
        }
        context.enable()
        try activate(context)

        XCTAssertTrue(context.process(type: .flagsChanged, event: try shiftEvent(isDown: false)))
        XCTAssertTrue(
            context.process(
                type: .tapDisabledByTimeout,
                event: try keyEvent(code: 0)
            )
        )
        XCTAssertEqual(
            effects.values.last,
            .listenerDisabled(GridActivation(generation: 1))
        )
    }

    func testEffectRelayPreservesSubmissionOrder() async {
        var delivered: [GridInputEffect] = []
        let deliveredThirdEffect = expectation(description: "third effect delivered")
        let relay = MacOSGridEventEffectRelay { effect in
            delivered.append(effect)
            if delivered.count == 3 {
                deliveredThirdEffect.fulfill()
            }
        }
        let activation = GridActivation(generation: 1)
        relay.submit(.activated(activation))
        relay.submit(.handoffCancelled(activation, .ordinaryKey))
        relay.submit(.listenerDisabled(nil))

        await fulfillment(of: [deliveredThirdEffect], timeout: 1)
        XCTAssertEqual(
            delivered,
            [
                .activated(activation),
                .handoffCancelled(activation, .ordinaryKey),
                .listenerDisabled(nil),
            ]
        )
    }

    private func shiftEvent(isDown: Bool) throws -> CGEvent {
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: isDown)
        )
        event.flags = isDown ? .maskShift : []
        return event
    }

    private func keyEvent(
        code: CGKeyCode,
        flags: CGEventFlags = []
    ) throws -> CGEvent {
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
        )
        event.flags = flags
        return event
    }

    private func activate(_ context: MacOSGridEventTapContext) throws {
        XCTAssertTrue(context.process(type: .flagsChanged, event: try shiftEvent(isDown: true)))
        XCTAssertTrue(context.process(type: .flagsChanged, event: try shiftEvent(isDown: false)))
        XCTAssertTrue(context.process(type: .flagsChanged, event: try shiftEvent(isDown: true)))
    }
}

private final class EffectCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [GridInputEffect] = []

    var values: [GridInputEffect] {
        lock.withLock { storage }
    }

    func append(_ effect: GridInputEffect) {
        lock.withLock {
            storage.append(effect)
        }
    }
}
