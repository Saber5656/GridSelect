@testable import GridSelectCore
import XCTest

@MainActor
final class SelectionModeCoordinatorTests: XCTestCase {
    private let rectangle = SelectionRectangle(
        displayID: 7,
        x: 120,
        y: 240,
        width: 80,
        height: 40
    )

    func testInstalledShortcutStartsAndCancelsSelection() async {
        let shortcut = ShortcutStub()
        let permission = PermissionStub(status: .granted)
        let overlay = ImmediateOverlayStub(result: .cancelled)
        let extractor = ExtractorStub(behavior: .succeed("unused"))
        let clipboard = ClipboardStub()
        let states = StateRecorder()
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: permission,
            overlay: overlay,
            extractor: extractor,
            clipboard: clipboard,
            states: states
        )

        XCTAssertTrue(coordinator.installShortcut())
        XCTAssertTrue(shortcut.trigger())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(states.values, [.selecting, .cancelled])
        XCTAssertEqual(coordinator.state, .cancelled)
        XCTAssertEqual(overlay.selectionCount, 1)
        XCTAssertEqual(overlay.dismissalCount, 1)
        let extractionCallCount = await extractor.callCount()
        XCTAssertEqual(extractionCallCount, 0)
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
    }

    func testConfirmedSelectionRunsExtractionAndCopyPipeline() async {
        let shortcut = ShortcutStub()
        let permission = PermissionStub(status: .granted)
        let overlay = ImmediateOverlayStub(
            result: .confirmed(rectangle),
            draggedRectangle: rectangle
        )
        let extractor = ExtractorStub(behavior: .succeed("alpha\nbravo"))
        let clipboard = ClipboardStub()
        let states = StateRecorder()
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: permission,
            overlay: overlay,
            extractor: extractor,
            clipboard: clipboard,
            states: states
        )

        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(
            states.values,
            [
                .selecting,
                .dragging(rectangle),
                .confirmed(rectangle),
                .extracting(rectangle),
                .copying,
                .completed
            ]
        )
        let extractedRectangles = await extractor.rectangles()
        XCTAssertEqual(extractedRectangles, [rectangle])
        XCTAssertEqual(clipboard.writtenTexts, ["alpha\nbravo"])
        XCTAssertEqual(coordinator.state, .completed)
        XCTAssertEqual(overlay.dismissalCount, 1)
    }

    func testMissingPermissionDoesNotPresentOverlay() async {
        let shortcut = ShortcutStub()
        let permission = PermissionStub(status: .required)
        let overlay = ImmediateOverlayStub(result: .cancelled)
        let extractor = ExtractorStub(behavior: .succeed("unused"))
        let clipboard = ClipboardStub()
        let states = StateRecorder()
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: permission,
            overlay: overlay,
            extractor: extractor,
            clipboard: clipboard,
            states: states
        )

        XCTAssertFalse(coordinator.activate())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(states.values, [.permissionRequired])
        XCTAssertEqual(coordinator.state, .permissionRequired)
        XCTAssertEqual(overlay.selectionCount, 0)
        let extractionCallCount = await extractor.callCount()
        XCTAssertEqual(extractionCallCount, 0)
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
    }

    func testImmediateCancelPreventsOverlayStartAndAllowsReentryAfterCleanup() async {
        let overlay = ImmediateOverlayStub(result: .cancelled)
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: overlay,
            extractor: ExtractorStub(behavior: .succeed("unused")),
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )

        XCTAssertTrue(coordinator.activate())
        XCTAssertTrue(coordinator.cancel())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(overlay.selectionCount, 0)
        XCTAssertEqual(coordinator.state, .cancelled)

        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()
        XCTAssertEqual(overlay.selectionCount, 1)
        XCTAssertEqual(coordinator.state, .cancelled)
    }

    func testImmediateShutdownPreventsOverlayStart() async {
        let shortcut = ShortcutStub()
        let overlay = ImmediateOverlayStub(result: .cancelled)
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: PermissionStub(status: .granted),
            overlay: overlay,
            extractor: ExtractorStub(behavior: .succeed("unused")),
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )

        XCTAssertTrue(coordinator.installShortcut())
        XCTAssertTrue(coordinator.activate())
        coordinator.shutdown()
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(overlay.selectionCount, 0)
        XCTAssertEqual(shortcut.unregisterCount, 1)
    }

    func testCancelledCallerTaskDoesNotLeaveOrphanedSelectingState() async {
        let overlay = ImmediateOverlayStub(result: .cancelled)
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: overlay,
            extractor: ExtractorStub(behavior: .succeed("unused")),
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )

        let activationTask = Task { @MainActor in
            coordinator.activate()
        }
        activationTask.cancel()

        let didActivate = await activationTask.value
        XCTAssertTrue(didActivate)
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .cancelled)
        XCTAssertEqual(overlay.selectionCount, 1)
    }

    func testInvalidSelectionCancelsBeforeExtraction() async {
        let invalidRectangle = SelectionRectangle(
            displayID: 7,
            x: 120,
            y: 240,
            width: 0,
            height: 40
        )
        let shortcut = ShortcutStub()
        let permission = PermissionStub(status: .granted)
        let overlay = ImmediateOverlayStub(result: .confirmed(invalidRectangle))
        let extractor = ExtractorStub(behavior: .succeed("unused"))
        let clipboard = ClipboardStub()
        let states = StateRecorder()
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: permission,
            overlay: overlay,
            extractor: extractor,
            clipboard: clipboard,
            states: states
        )

        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(states.values, [.selecting, .cancelled])
        let extractionCallCount = await extractor.callCount()
        XCTAssertEqual(extractionCallCount, 0)
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
    }

    func testOverlayFailureLeavesCoordinatorRecoverable() async {
        let shortcut = ShortcutStub()
        let permission = PermissionStub(status: .granted)
        let overlay = ImmediateOverlayStub(result: .cancelled)
        overlay.shouldFail = true
        let extractor = ExtractorStub(behavior: .succeed("unused"))
        let clipboard = ClipboardStub()
        let states = StateRecorder()
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: permission,
            overlay: overlay,
            extractor: extractor,
            clipboard: clipboard,
            states: states
        )

        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()
        XCTAssertEqual(coordinator.state, .failed(.overlayFailed))

        overlay.shouldFail = false
        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .cancelled)
        XCTAssertEqual(
            states.values,
            [
                .selecting,
                .failed(.overlayFailed),
                .selecting,
                .cancelled
            ]
        )
    }

    func testSelectingObserverCancelPreventsSessionTaskCreation() async {
        let overlay = ImmediateOverlayStub(result: .cancelled)
        let extractor = ExtractorStub(behavior: .succeed("unused"))
        let states = StateRecorder()
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: overlay,
            extractor: extractor,
            clipboard: ClipboardStub(),
            states: states
        )
        states.onRecord = { [weak coordinator] state in
            if state == .selecting {
                coordinator?.cancel()
            }
        }

        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .cancelled)
        XCTAssertEqual(overlay.selectionCount, 0)
        let extractionCallCount = await extractor.callCount()
        XCTAssertEqual(extractionCallCount, 0)
    }

    func testConfirmedObserverCancelPreventsExtraction() async {
        let extractor = ExtractorStub(behavior: .succeed("unused"))
        let states = StateRecorder()
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(result: .confirmed(rectangle)),
            extractor: extractor,
            clipboard: ClipboardStub(),
            states: states
        )
        states.onRecord = { [weak coordinator] state in
            if case .confirmed = state {
                coordinator?.cancel()
            }
        }

        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .cancelled)
        let extractionCallCount = await extractor.callCount()
        XCTAssertEqual(extractionCallCount, 0)
    }

    func testExtractingObserverCancelPreventsExtraction() async {
        let extractor = ExtractorStub(behavior: .succeed("unused"))
        let states = StateRecorder()
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(result: .confirmed(rectangle)),
            extractor: extractor,
            clipboard: ClipboardStub(),
            states: states
        )
        states.onRecord = { [weak coordinator] state in
            if case .extracting = state {
                coordinator?.cancel()
            }
        }

        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .cancelled)
        let extractionCallCount = await extractor.callCount()
        XCTAssertEqual(extractionCallCount, 0)
    }

    func testCopyingObserverCancelPreventsClipboardWrite() async {
        let extractor = ExtractorStub(behavior: .succeed("selected"))
        let clipboard = ClipboardStub()
        let states = StateRecorder()
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(result: .confirmed(rectangle)),
            extractor: extractor,
            clipboard: clipboard,
            states: states
        )
        states.onRecord = { [weak coordinator] state in
            if state == .copying {
                coordinator?.cancel()
            }
        }

        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .cancelled)
        let extractionCallCount = await extractor.callCount()
        XCTAssertEqual(extractionCallCount, 1)
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
    }

    func testExtractionAndClipboardFailuresAreTyped() async {
        let permission = PermissionStub(status: .granted)

        let extractionOverlay = ImmediateOverlayStub(result: .confirmed(rectangle))
        let extractionFailure = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: permission,
            overlay: extractionOverlay,
            extractor: ExtractorStub(behavior: .fail),
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )
        XCTAssertTrue(extractionFailure.activate())
        await extractionFailure.waitForMostRecentSession()
        XCTAssertEqual(extractionFailure.state, .failed(.extractionFailed))
        XCTAssertEqual(extractionOverlay.dismissalCount, 1)

        let clipboard = ClipboardStub()
        clipboard.shouldFail = true
        let clipboardFailure = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: permission,
            overlay: ImmediateOverlayStub(result: .confirmed(rectangle)),
            extractor: ExtractorStub(behavior: .succeed("selected")),
            clipboard: clipboard,
            states: StateRecorder()
        )
        XCTAssertTrue(clipboardFailure.activate())
        await clipboardFailure.waitForMostRecentSession()
        XCTAssertEqual(clipboardFailure.state, .failed(.clipboardWriteFailed))
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
    }

    func testEmptyExtractionDoesNotWriteClipboard() async {
        let clipboard = ClipboardStub()
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(result: .confirmed(rectangle)),
            extractor: ExtractorStub(behavior: .succeed("")),
            clipboard: clipboard,
            states: StateRecorder()
        )

        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .cancelled)
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
    }

    func testPermissionRevokedDuringExtractionReturnsPermissionState() async {
        let clipboard = ClipboardStub()
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(result: .confirmed(rectangle)),
            extractor: ExtractorStub(behavior: .permissionRequired),
            clipboard: clipboard,
            states: StateRecorder()
        )

        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .permissionRequired)
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
    }

    func testReentryIsIgnoredAndCancellationCleansActiveOverlay() async {
        let overlay = SuspendingOverlayStub()
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: overlay,
            extractor: ExtractorStub(behavior: .succeed("unused")),
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )

        XCTAssertTrue(coordinator.activate())
        XCTAssertFalse(coordinator.activate())
        await overlay.waitUntilSelectionCount(1)

        XCTAssertTrue(coordinator.cancel())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(overlay.selectionCount, 1)
        XCTAssertEqual(overlay.dismissalCount, 1)
        XCTAssertEqual(coordinator.state, .cancelled)
        XCTAssertFalse(coordinator.cancel())
    }

    func testCancellationDuringNonCooperativeExtractionAllowsReentryAndDiscardsLateResult() async {
        let overlay = ImmediateOverlayStub(result: .confirmed(rectangle))
        let extractor = ControlledExtractorStub()
        let clipboard = ClipboardStub()
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: overlay,
            extractor: extractor,
            clipboard: clipboard,
            states: StateRecorder()
        )

        XCTAssertTrue(coordinator.activate())
        await extractor.waitUntilStarted()
        XCTAssertEqual(coordinator.state, .extracting(rectangle))

        XCTAssertTrue(coordinator.cancel())
        overlay.result = .cancelled
        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .cancelled)
        XCTAssertEqual(overlay.selectionCount, 2)
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)

        await extractor.succeed(with: "stale result")
        await coordinator.waitForAllSessionCleanup()

        XCTAssertEqual(coordinator.state, .cancelled)
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
    }

    func testLateDragFromConfirmedSessionCannotRegressPipelineState() async {
        let overlay = ImmediateOverlayStub(result: .confirmed(rectangle))
        let extractor = ControlledExtractorStub()
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: overlay,
            extractor: extractor,
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )

        XCTAssertTrue(coordinator.activate())
        await extractor.waitUntilStarted()
        XCTAssertEqual(coordinator.state, .extracting(rectangle))

        overlay.emitDrag(
            SelectionRectangle(
                displayID: 7,
                x: 10,
                y: 20,
                width: 30,
                height: 40
            )
        )
        XCTAssertEqual(coordinator.state, .extracting(rectangle))

        XCTAssertTrue(coordinator.cancel())
        await extractor.succeed(with: "stale result")
        await coordinator.waitForMostRecentSession()
    }

    func testStaleOverlayCallbackDoesNotMutateNewSession() async {
        let overlay = SuspendingOverlayStub()
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: overlay,
            extractor: ExtractorStub(behavior: .succeed("unused")),
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )

        XCTAssertTrue(coordinator.activate())
        await overlay.waitUntilSelectionCount(1)
        XCTAssertTrue(coordinator.cancel())
        await coordinator.waitForMostRecentSession()

        XCTAssertTrue(coordinator.activate())
        await overlay.waitUntilSelectionCount(2)
        overlay.emitDrag(rectangle, fromSelectionAt: 0)

        XCTAssertEqual(coordinator.state, .selecting)
        XCTAssertTrue(coordinator.cancel())
        await coordinator.waitForMostRecentSession()
    }

    func testShortcutRegistrationFailureIsTypedAndRetryable() async {
        let shortcut = ShortcutStub()
        shortcut.shouldFailRegistration = true
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(result: .cancelled),
            extractor: ExtractorStub(behavior: .succeed("unused")),
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )

        XCTAssertFalse(coordinator.installShortcut())
        XCTAssertEqual(coordinator.state, .failed(.shortcutRegistrationFailed))

        shortcut.shouldFailRegistration = false
        XCTAssertTrue(coordinator.installShortcut())
        XCTAssertTrue(shortcut.trigger())
        await coordinator.waitForMostRecentSession()
        XCTAssertEqual(coordinator.state, .cancelled)
    }

    func testShutdownCancelsSessionAndUnregistersShortcut() async {
        let shortcut = ShortcutStub()
        let overlay = SuspendingOverlayStub()
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: PermissionStub(status: .granted),
            overlay: overlay,
            extractor: ExtractorStub(behavior: .succeed("unused")),
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )

        XCTAssertTrue(coordinator.installShortcut())
        XCTAssertTrue(coordinator.activate())
        await overlay.waitUntilSelectionCount(1)

        coordinator.shutdown()
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(shortcut.unregisterCount, 1)
        XCTAssertEqual(overlay.dismissalCount, 1)
    }

    func testQueuedShortcutCallbackAfterShutdownAndReinstallIsIgnored() async {
        let shortcut = ShortcutStub()
        let overlay = ImmediateOverlayStub(result: .cancelled)
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: PermissionStub(status: .granted),
            overlay: overlay,
            extractor: ExtractorStub(behavior: .succeed("unused")),
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )

        XCTAssertTrue(coordinator.installShortcut())
        coordinator.shutdown()
        XCTAssertTrue(shortcut.triggerRegisteredHandler(at: 0))

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(overlay.selectionCount, 0)

        XCTAssertTrue(coordinator.installShortcut())
        XCTAssertTrue(shortcut.triggerRegisteredHandler(at: 0))
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(overlay.selectionCount, 0)

        XCTAssertTrue(shortcut.triggerRegisteredHandler(at: 1))
        await coordinator.waitForMostRecentSession()
        XCTAssertEqual(coordinator.state, .cancelled)
        XCTAssertEqual(overlay.selectionCount, 1)
    }

    private func makeCoordinator(
        shortcut: ShortcutStub,
        permission: PermissionStub,
        overlay: any SelectionOverlayPresenting,
        extractor: any RectangularTextExtracting,
        clipboard: ClipboardStub,
        states: StateRecorder
    ) -> SelectionModeCoordinator {
        SelectionModeCoordinator(
            shortcut: shortcut,
            permissionChecker: permission,
            overlay: overlay,
            extractor: extractor,
            clipboard: clipboard,
            stateObserver: { state in
                states.record(state)
            }
        )
    }

}

private enum TestFailure: Error, Sendable {
    case expected
}

@MainActor
private final class ShortcutStub: SelectionShortcutRegistering {
    var shouldFailRegistration = false
    private var handler: (@MainActor @Sendable () -> Void)?
    private var registeredHandlers: [
        @MainActor @Sendable () -> Void
    ] = []
    private(set) var unregisterCount = 0

    func registerActivationHandler(
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) throws {
        if shouldFailRegistration {
            throw TestFailure.expected
        }
        self.handler = handler
        registeredHandlers.append(handler)
    }

    func unregister() {
        unregisterCount += 1
        handler = nil
    }

    @discardableResult
    func trigger() -> Bool {
        guard let handler else {
            return false
        }
        handler()
        return true
    }

    @discardableResult
    func triggerRegisteredHandler(at index: Int) -> Bool {
        guard registeredHandlers.indices.contains(index) else {
            return false
        }
        registeredHandlers[index]()
        return true
    }
}

@MainActor
private final class PermissionStub: SelectionPermissionChecking {
    var selectionPermissionStatus: SelectionPermissionStatus

    init(status: SelectionPermissionStatus) {
        selectionPermissionStatus = status
    }
}

@MainActor
private final class ImmediateOverlayStub: SelectionOverlayPresenting {
    var shouldFail = false
    var result: SelectionOverlayResult
    private let draggedRectangle: SelectionRectangle?
    private var dragHandler: (
        @MainActor @Sendable (SelectionRectangle) -> Void
    )?
    private(set) var selectionCount = 0
    private(set) var dismissalCount = 0

    init(
        result: SelectionOverlayResult,
        draggedRectangle: SelectionRectangle? = nil
    ) {
        self.result = result
        self.draggedRectangle = draggedRectangle
    }

    func select(
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult {
        selectionCount += 1
        dragHandler = onDrag
        if shouldFail {
            throw TestFailure.expected
        }
        if let draggedRectangle {
            onDrag(draggedRectangle)
        }
        return result
    }

    func dismissSelection() {
        dismissalCount += 1
    }

    func emitDrag(_ rectangle: SelectionRectangle) {
        dragHandler?(rectangle)
    }
}

@MainActor
private final class SuspendingOverlayStub: SelectionOverlayPresenting {
    private struct SelectionWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var continuation: CheckedContinuation<SelectionOverlayResult, any Error>?
    private var dragHandlers: [
        @MainActor @Sendable (SelectionRectangle) -> Void
    ] = []
    private var selectionWaiters: [SelectionWaiter] = []
    private(set) var selectionCount = 0
    private(set) var dismissalCount = 0

    func select(
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult {
        selectionCount += 1
        dragHandlers.append(onDrag)
        resumeSelectionWaiters()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func dismissSelection() {
        dismissalCount += 1
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    func emitDrag(_ rectangle: SelectionRectangle, fromSelectionAt index: Int) {
        dragHandlers[index](rectangle)
    }

    func waitUntilSelectionCount(_ expectedCount: Int) async {
        guard selectionCount < expectedCount else {
            return
        }

        await withCheckedContinuation { continuation in
            selectionWaiters.append(
                SelectionWaiter(
                    expectedCount: expectedCount,
                    continuation: continuation
                )
            )
        }
    }

    private func resumeSelectionWaiters() {
        var pending: [SelectionWaiter] = []
        for waiter in selectionWaiters {
            if selectionCount >= waiter.expectedCount {
                waiter.continuation.resume()
            } else {
                pending.append(waiter)
            }
        }
        selectionWaiters = pending
    }
}

private actor ExtractorStub: RectangularTextExtracting {
    enum Behavior: Sendable {
        case succeed(String)
        case fail
        case permissionRequired
    }

    private let behavior: Behavior
    private var receivedRectangles: [SelectionRectangle] = []

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func extractText(in rectangle: SelectionRectangle) async throws -> String {
        receivedRectangles.append(rectangle)
        switch behavior {
        case let .succeed(text):
            return text
        case .fail:
            throw TestFailure.expected
        case .permissionRequired:
            throw SelectionPermissionRequiredError()
        }
    }

    func callCount() -> Int {
        receivedRectangles.count
    }

    func rectangles() -> [SelectionRectangle] {
        receivedRectangles
    }
}

private actor ControlledExtractorStub: RectangularTextExtracting {
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<String, any Error>?
    private(set) var hasStarted = false
    private(set) var hasReturned = false

    func extractText(in rectangle: SelectionRectangle) async throws -> String {
        hasStarted = true
        startedWaiters.forEach { $0.resume() }
        startedWaiters.removeAll()
        let text = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
        hasReturned = true
        return text
    }

    func succeed(with text: String) {
        continuation?.resume(returning: text)
        continuation = nil
    }

    func waitUntilStarted() async {
        guard !hasStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }
}

@MainActor
private final class ClipboardStub: ClipboardWriting {
    var shouldFail = false
    private(set) var writtenTexts: [String] = []

    func writePlainText(_ text: String) throws {
        if shouldFail {
            throw TestFailure.expected
        }
        writtenTexts.append(text)
    }
}

@MainActor
private final class StateRecorder {
    private(set) var values: [SelectionModeState] = []
    var onRecord: (@MainActor (SelectionModeState) -> Void)?

    func record(_ state: SelectionModeState) {
        values.append(state)
        onRecord?(state)
    }
}
