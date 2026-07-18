@testable import GridSelect
import CoreGraphics
import Dispatch
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

    func testTimeoutCancelsCaptureDiscardsQueueAndRejectsLateResult() async throws {
        let context = MacOSGridEventTapContext(doubleClickInterval: 1) { _ in }
        context.enable()
        try activate(context)
        let activation = GridActivation(generation: 1)
        XCTAssertFalse(context.process(type: .keyDown, event: try keyEvent(code: 124)))

        let sourceContext = testSourceContext(for: activation)
        let captureGate = LateCaretCaptureGate()
        let cancellationDelivered = expectation(description: "timeout cancellation delivered")
        let lateCaptureDiscarded = expectation(description: "late capture context discarded")
        var delivered: [SelectionShortcutEvent] = []
        let shortcut = MacOSGlobalShortcut(
            handoffTimeout: .milliseconds(20),
            sourceContextCapturer: { _ in sourceContext },
            caretCaptureAdapter: MacOSCaretCaptureAdapter(
                capture: { _ in captureGate.capture() },
                discard: { _ in lateCaptureDiscarded.fulfill() }
            ),
            callbackContext: context,
            eventHandler: { event in
                delivered.append(event)
                if event == .handoffCancelled(activation, .timedOut) {
                    cancellationDelivered.fulfill()
                }
            }
        )
        defer {
            captureGate.release()
            shortcut.unregister()
        }

        shortcut.handleInputEffect(.activated(activation))
        await Task.yield()
        XCTAssertTrue(captureGate.waitUntilStarted())
        await fulfillment(of: [cancellationDelivered], timeout: 1)

        XCTAssertEqual(delivered, [.handoffCancelled(activation, .timedOut)])
        XCTAssertNil(context.cancelHandoff(for: activation, reason: .timedOut))
        XCTAssertNil(shortcut.completeHandoff(for: activation))
        XCTAssertTrue(context.process(type: .keyDown, event: try keyEvent(code: 124)))

        captureGate.release()
        await fulfillment(of: [lateCaptureDiscarded], timeout: 1)
        await Task.yield()

        XCTAssertEqual(delivered, [.handoffCancelled(activation, .timedOut)])
    }

    func testCaretUnavailableBeforeDeadlineStillActivatesMouseFallback() async throws {
        let context = MacOSGridEventTapContext(doubleClickInterval: 1) { _ in }
        context.enable()
        try activate(context)
        let activation = GridActivation(generation: 1)
        XCTAssertFalse(context.process(type: .keyDown, event: try keyEvent(code: 124)))

        let sourceContext = testSourceContext(for: activation)
        let activated = expectation(description: "mouse fallback activated")
        let discardCount = LockedCounter()
        var delivered: [SelectionShortcutEvent] = []
        let shortcut = MacOSGlobalShortcut(
            sourceContextCapturer: { _ in sourceContext },
            caretCaptureAdapter: MacOSCaretCaptureAdapter(
                capture: { _ in .unavailable },
                discard: { _ in discardCount.increment() }
            ),
            callbackContext: context,
            eventHandler: { event in
                delivered.append(event)
                if event == .activated(sourceContext) {
                    activated.fulfill()
                }
            }
        )
        defer { shortcut.unregister() }

        shortcut.handleInputEffect(.activated(activation))
        await fulfillment(of: [activated], timeout: 1)

        XCTAssertEqual(shortcut.completeHandoff(for: activation), [.move(.right)])
        try await Task.sleep(for: .milliseconds(550))

        XCTAssertEqual(delivered, [.activated(sourceContext)])
        XCTAssertEqual(discardCount.value, 0)
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

    private func testSourceContext(for activation: GridActivation) -> ActivationSourceContext {
        let frame = ScreenRectangle(x: 0, y: 0, width: 1_000, height: 800)
        return ActivationSourceContext(
            activation: activation,
            sessionIdentity: SelectionSessionIdentity(rawValue: activation.generation),
            source: SelectionSourceIdentity(
                processIdentifier: 10,
                windowIdentifier: 20
            ),
            sourceWindowFrame: frame,
            displays: [
                DisplayGeometry(
                    displayID: 1,
                    appKitFrame: frame,
                    coreGraphicsBounds: frame,
                    backingScale: 2
                ),
            ],
            caretCandidate: nil
        )
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

private final class LateCaretCaptureGate: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let completion = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var isReleased = false

    func capture() -> MacOSCaretCaptureResult {
        started.signal()
        completion.wait()
        return .unavailable
    }

    func waitUntilStarted() -> Bool {
        started.wait(timeout: .now() + 1) == .success
    }

    func release() {
        let shouldSignal = lock.withLock { () -> Bool in
            guard !isReleased else {
                return false
            }
            isReleased = true
            return true
        }
        if shouldSignal {
            completion.signal()
        }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() {
        lock.withLock {
            storage += 1
        }
    }
}
