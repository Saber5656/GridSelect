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

    func testDoubleShiftPathCannotUseUnboundCopyTimeHitTesting() async {
        let shortcut = ShortcutStub()
        let extractor = ExtractorStub(behavior: .succeed("must not be read"))
        let clipboard = ClipboardStub()
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(result: .confirmed(rectangle)),
            extractor: extractor,
            clipboard: clipboard,
            states: StateRecorder()
        )
        XCTAssertTrue(coordinator.installShortcut())

        XCTAssertTrue(shortcut.trigger())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .failed(.extractionFailed))
        let extractionCallCount = await extractor.callCount()
        XCTAssertEqual(extractionCallCount, 0)
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
    }

    func testConfirmedSelectionNormalizesTextBeforeClipboardWrite() async {
        let clipboard = ClipboardStub()
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(result: .confirmed(rectangle)),
            extractor: ExtractorStub(behavior: .succeed("alpha  \r\nbravo  \r\n")),
            clipboard: clipboard,
            states: StateRecorder()
        )

        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(clipboard.writtenTexts, ["alpha  \nbravo  "])
        XCTAssertEqual(coordinator.state, .completed)
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

    func testControlledExtractorConsumesResultCompletedBeforeStart() async throws {
        let extractor = ControlledExtractorStub()

        await extractor.succeed(with: "latched result")
        let result = try await extractor.extractText(in: rectangle)

        XCTAssertEqual(result, "latched result")
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
        guard await overlay.waitUntilSelectionCount(1) else {
            XCTFail("Timed out waiting for the selection overlay to start")
            coordinator.shutdown()
            await coordinator.waitForAllSessionCleanup()
            return
        }

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
        guard await extractor.waitUntilStarted() else {
            XCTFail("Timed out waiting for text extraction to start")
            coordinator.cancel()
            await extractor.succeed(with: "cleanup")
            await coordinator.waitForAllSessionCleanup()
            return
        }
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
        guard await extractor.waitUntilStarted() else {
            XCTFail("Timed out waiting for text extraction to start")
            coordinator.cancel()
            await extractor.succeed(with: "cleanup")
            await coordinator.waitForAllSessionCleanup()
            return
        }
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
        guard await overlay.waitUntilSelectionCount(1) else {
            XCTFail("Timed out waiting for the first selection overlay to start")
            coordinator.shutdown()
            await coordinator.waitForAllSessionCleanup()
            return
        }
        XCTAssertTrue(coordinator.cancel())
        await coordinator.waitForMostRecentSession()

        XCTAssertTrue(coordinator.activate())
        guard await overlay.waitUntilSelectionCount(2) else {
            XCTFail("Timed out waiting for the second selection overlay to start")
            coordinator.shutdown()
            await coordinator.waitForAllSessionCleanup()
            return
        }
        overlay.emitDrag(rectangle, fromSelectionAt: 0)

        XCTAssertEqual(coordinator.state, .selecting)
        XCTAssertTrue(coordinator.cancel())
        await coordinator.waitForMostRecentSession()
    }

    func testShortcutRegistrationFailureIsTypedAndRetryable() async {
        let shortcut = ShortcutStub()
        shortcut.shouldFailRegistration = true
        let states = StateRecorder()
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(result: .cancelled),
            extractor: ExtractorStub(behavior: .succeed("unused")),
            clipboard: ClipboardStub(),
            states: states
        )

        XCTAssertFalse(coordinator.installShortcut())
        XCTAssertEqual(coordinator.state, .failed(.shortcutRegistrationFailed))
        XCTAssertEqual(states.values, [.failed(.shortcutRegistrationFailed)])

        shortcut.shouldFailRegistration = false
        XCTAssertTrue(coordinator.installShortcut())
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(
            states.values,
            [.failed(.shortcutRegistrationFailed), .idle]
        )

        XCTAssertTrue(shortcut.trigger())
        await coordinator.waitForMostRecentSession()
        XCTAssertEqual(coordinator.state, .cancelled)
        XCTAssertEqual(
            states.values,
            [
                .failed(.shortcutRegistrationFailed),
                .idle,
                .selecting,
                .cancelled
            ]
        )
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
        guard await overlay.waitUntilSelectionCount(1) else {
            XCTFail("Timed out waiting for the selection overlay to start")
            coordinator.shutdown()
            await coordinator.waitForAllSessionCleanup()
            return
        }

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

    func testShortcutHandoffDrainsAtOverlayReadiness() async {
        let shortcut = ShortcutStub()
        shortcut.handoffCommands = [.move(.right), .freeze, .move(.right)]
        let overlay = HandoffCapturingOverlayStub()
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: PermissionStub(status: .granted),
            overlay: overlay,
            extractor: ExtractorStub(behavior: .succeed("unused")),
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )
        XCTAssertTrue(coordinator.installShortcut())

        XCTAssertTrue(shortcut.trigger())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(shortcut.completedActivations, [GridActivation(generation: 1)])
        XCTAssertEqual(overlay.sourceContext?.activation, GridActivation(generation: 1))
        XCTAssertEqual(
            overlay.handoffCommands,
            [.move(.right), .freeze, .move(.right)]
        )
        XCTAssertEqual(coordinator.state, .cancelled)
    }

    func testListenerDisablementFailsClosedAfterHandoff() async {
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
        XCTAssertTrue(shortcut.trigger())
        guard await overlay.waitUntilSelectionCount(1) else {
            XCTFail("Timed out waiting for the selection overlay to start")
            return
        }

        shortcut.triggerListenerDisabled()
        await coordinator.waitForAllSessionCleanup()

        XCTAssertEqual(coordinator.state, .failed(.listenerDisabled))
        XCTAssertEqual(overlay.dismissalCount, 1)
    }

    func testOverlaySetupFailureCancelsPendingHandoff() async {
        let shortcut = ShortcutStub()
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: PermissionStub(status: .granted),
            overlay: PreReadyFailingOverlayStub(),
            extractor: ExtractorStub(behavior: .succeed("unused")),
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )
        XCTAssertTrue(coordinator.installShortcut())

        XCTAssertTrue(shortcut.trigger())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .failed(.overlayFailed))
        XCTAssertEqual(shortcut.completedActivations, [])
        XCTAssertEqual(shortcut.cancelledActivations, [GridActivation(generation: 1)])
    }

    func testListenerCanBeExplicitlyReinstalledAfterDisablement() async {
        let shortcut = ShortcutStub()
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(result: .cancelled),
            extractor: ExtractorStub(behavior: .succeed("unused")),
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )
        XCTAssertTrue(coordinator.installShortcut())
        shortcut.triggerListenerDisabled()
        XCTAssertEqual(coordinator.state, .failed(.listenerDisabled))
        XCTAssertEqual(shortcut.unregisterCount, 1)

        XCTAssertTrue(coordinator.installShortcut())
        XCTAssertEqual(coordinator.state, .idle)
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
    private var handler: (@MainActor @Sendable (SelectionShortcutEvent) -> Void)?
    private var registeredHandlers: [
        @MainActor @Sendable (SelectionShortcutEvent) -> Void
    ] = []
    private(set) var unregisterCount = 0
    private var nextGeneration: UInt64 = 0
    var handoffCommands: [GridHandoffCommand] = []
    private(set) var completedActivations: [GridActivation] = []
    private(set) var cancelledActivations: [GridActivation] = []

    func registerEventHandler(
        _ handler: @escaping @MainActor @Sendable (SelectionShortcutEvent) -> Void
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

    func completeHandoff(for activation: GridActivation) -> [GridHandoffCommand]? {
        completedActivations.append(activation)
        return handoffCommands
    }

    func cancelHandoff(
        for activation: GridActivation,
        reason: GridActivationCancellationReason
    ) {
        cancelledActivations.append(activation)
    }

    @discardableResult
    func trigger() -> Bool {
        guard let handler else {
            return false
        }
        nextGeneration += 1
        handler(.activated(testSourceContext(generation: nextGeneration)))
        return true
    }

    @discardableResult
    func triggerRegisteredHandler(at index: Int) -> Bool {
        guard registeredHandlers.indices.contains(index) else {
            return false
        }
        nextGeneration += 1
        registeredHandlers[index](
            .activated(testSourceContext(generation: nextGeneration))
        )
        return true
    }

    func triggerListenerDisabled() {
        handler?(.listenerDisabled)
    }

    private func testSourceContext(generation: UInt64) -> ActivationSourceContext {
        ActivationSourceContext(
            activation: GridActivation(generation: generation),
            source: SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 7),
            sourceWindowFrame: ScreenRectangle(x: 0, y: 0, width: 100, height: 100),
            displays: [
                DisplayGeometry(
                    displayID: 1,
                    appKitFrame: ScreenRectangle(x: 0, y: 0, width: 100, height: 100),
                    coreGraphicsBounds: ScreenRectangle(x: 0, y: 0, width: 100, height: 100),
                    backingScale: 2
                ),
            ],
            caretCandidate: nil
        )
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
private final class HandoffCapturingOverlayStub: SelectionOverlayPresenting {
    private(set) var handoffCommands: [GridHandoffCommand]?
    private(set) var sourceContext: ActivationSourceContext?

    func select(
        sourceContext: ActivationSourceContext?,
        onReady: @escaping @MainActor @Sendable () -> [GridHandoffCommand]?,
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult {
        self.sourceContext = sourceContext
        handoffCommands = onReady()
        return .cancelled
    }

    func select(
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult {
        .cancelled
    }

    func dismissSelection() {}
}

@MainActor
private final class PreReadyFailingOverlayStub: SelectionOverlayPresenting {
    func select(
        sourceContext: ActivationSourceContext?,
        onReady: @escaping @MainActor @Sendable () -> [GridHandoffCommand]?,
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult {
        throw TestFailure.expected
    }

    func select(
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult {
        throw TestFailure.expected
    }

    func dismissSelection() {}
}

@MainActor
private final class SuspendingOverlayStub: SelectionOverlayPresenting {
    private struct SelectionWaiter {
        let expectedCount: Int
        let expectation: XCTestExpectation
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

    func waitUntilSelectionCount(
        _ expectedCount: Int,
        timeout: TimeInterval = 2.0
    ) async -> Bool {
        guard selectionCount < expectedCount else {
            return true
        }

        let expectation = XCTestExpectation(
            description: "Selection count reaches \(expectedCount)"
        )
        selectionWaiters.append(
            SelectionWaiter(
                expectedCount: expectedCount,
                expectation: expectation
            )
        )

        let result = await XCTWaiter().fulfillment(
            of: [expectation],
            timeout: timeout
        )
        selectionWaiters.removeAll { $0.expectation === expectation }
        return result == .completed
    }

    private func resumeSelectionWaiters() {
        var pending: [SelectionWaiter] = []
        for waiter in selectionWaiters {
            if selectionCount >= waiter.expectedCount {
                waiter.expectation.fulfill()
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
    private var startedExpectations: [XCTestExpectation] = []
    private var continuation: CheckedContinuation<String, any Error>?
    private var pendingResult: String?
    private(set) var hasStarted = false
    private(set) var hasReturned = false

    func extractText(in rectangle: SelectionRectangle) async throws -> String {
        hasStarted = true
        startedExpectations.forEach { $0.fulfill() }
        startedExpectations.removeAll()

        if let pendingResult {
            self.pendingResult = nil
            hasReturned = true
            return pendingResult
        }

        let text = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
        hasReturned = true
        return text
    }

    func succeed(with text: String) {
        guard let continuation else {
            pendingResult = text
            return
        }

        self.continuation = nil
        continuation.resume(returning: text)
    }

    func waitUntilStarted(timeout: TimeInterval = 2.0) async -> Bool {
        guard !hasStarted else {
            return true
        }

        let expectation = XCTestExpectation(
            description: "Text extraction starts"
        )
        startedExpectations.append(expectation)

        let result = await XCTWaiter().fulfillment(
            of: [expectation],
            timeout: timeout
        )
        startedExpectations.removeAll { $0 === expectation }
        return result == .completed
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
