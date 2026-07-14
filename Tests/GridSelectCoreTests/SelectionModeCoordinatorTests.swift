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

    func testDoubleShiftBoundSelectionUsesBoundExtractorAndDiscardsContext() async {
        let shortcut = ShortcutStub()
        let activation = GridActivation(generation: 1)
        let session = SelectionSessionIdentity(rawValue: 1)
        let source = SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 7)
        let window = ScreenRectangle(x: 0, y: 0, width: 100, height: 100)
        let display = DisplayGeometry(
            displayID: 7,
            appKitFrame: window,
            coreGraphicsBounds: window,
            backingScale: 2
        )
        let boundContext = BoundSelectionContext(
            activation: activation,
            sessionIdentity: session,
            source: source,
            sourceWindowFrame: window,
            element: SelectionElementIdentity(rawValue: 9),
            anchor: GridBoundary(row: 0, column: 0),
            sourceRange: 0..<10,
            display: display
        )
        let extractor = BoundExtractorStub(text: "bound text")
        let clipboard = ClipboardStub()
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(
                result: .boundConfirmed(rectangle, boundContext)
            ),
            extractor: extractor,
            clipboard: clipboard,
            states: StateRecorder()
        )
        XCTAssertTrue(coordinator.installShortcut())

        XCTAssertTrue(shortcut.trigger())
        await coordinator.waitForMostRecentSession()
        await coordinator.waitForAllSessionCleanup()

        let calls = await extractor.calls()
        XCTAssertEqual(calls.unbound, 0)
        XCTAssertEqual(calls.bound, [boundContext])
        XCTAssertEqual(calls.authorized, [boundContext])
        XCTAssertEqual(calls.discarded, [session])
        XCTAssertEqual(clipboard.writtenTexts, ["bound text"])
        XCTAssertEqual(coordinator.state, .completed)
    }

    func testSourceFailureIsActionableAndDiscardsSession() async {
        let shortcut = ShortcutStub()
        let extractor = BoundExtractorStub(text: "unused")
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(
                result: .sourceFailed(.secureInputUnsupported)
            ),
            extractor: extractor,
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )
        XCTAssertTrue(coordinator.installShortcut())

        XCTAssertTrue(shortcut.trigger())
        await coordinator.waitForMostRecentSession()
        await coordinator.waitForAllSessionCleanup()

        XCTAssertEqual(coordinator.state, .failed(.secureInputUnsupported))
        let failureCalls = await extractor.calls()
        XCTAssertEqual(
            failureCalls.discarded,
            [SelectionSessionIdentity(rawValue: 1)]
        )
    }

    func testRejectedConcurrentActivationDiscardsOnlyRejectedSession() async {
        let shortcut = ShortcutStub()
        let overlay = SuspendingOverlayStub()
        let extractor = BoundExtractorStub(text: "unused")
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: PermissionStub(status: .granted),
            overlay: overlay,
            extractor: extractor,
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )
        XCTAssertTrue(coordinator.installShortcut())
        XCTAssertTrue(shortcut.trigger())
        guard await overlay.waitUntilSelectionCount(1) else {
            return XCTFail("First selection did not start")
        }

        XCTAssertTrue(shortcut.trigger())
        await coordinator.waitForContextCleanup()
        let rejectedCalls = await extractor.calls()
        XCTAssertEqual(
            rejectedCalls.discarded,
            [SelectionSessionIdentity(rawValue: 2)]
        )

        XCTAssertTrue(coordinator.cancel())
        await coordinator.waitForAllSessionCleanup()
        let finalCalls = await extractor.calls()
        XCTAssertEqual(
            Set(finalCalls.discarded),
            Set([
                SelectionSessionIdentity(rawValue: 1),
                SelectionSessionIdentity(rawValue: 2),
            ])
        )
    }

    func testConcurrentSourceCaptureFailureDoesNotCorruptActiveSession() async {
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
            return XCTFail("Selection did not start")
        }

        shortcut.triggerSourceCaptureFailure(.secureInputUnsupported)

        XCTAssertEqual(coordinator.state, .selecting)
        XCTAssertTrue(coordinator.cancel())
        await coordinator.waitForAllSessionCleanup()
        XCTAssertEqual(coordinator.state, .cancelled)
    }

    func testBoundConfirmationRejectsDifferentSessionIdentity() async {
        let shortcut = ShortcutStub()
        let source = SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 7)
        let window = ScreenRectangle(x: 0, y: 0, width: 100, height: 100)
        let context = BoundSelectionContext(
            activation: GridActivation(generation: 1),
            sessionIdentity: SelectionSessionIdentity(rawValue: 999),
            source: source,
            sourceWindowFrame: window,
            element: SelectionElementIdentity(rawValue: 4),
            anchor: GridBoundary(row: 0, column: 0),
            sourceRange: 0..<0,
            display: DisplayGeometry(
                displayID: 7,
                appKitFrame: window,
                coreGraphicsBounds: window,
                backingScale: 2
            )
        )
        let extractor = BoundExtractorStub(text: "must not extract")
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(result: .boundConfirmed(rectangle, context)),
            extractor: extractor,
            clipboard: ClipboardStub(),
            states: StateRecorder()
        )
        XCTAssertTrue(coordinator.installShortcut())

        XCTAssertTrue(shortcut.trigger())
        await coordinator.waitForMostRecentSession()
        await coordinator.waitForAllSessionCleanup()

        XCTAssertEqual(coordinator.state, .failed(.extractionFailed))
        let calls = await extractor.calls()
        XCTAssertTrue(calls.bound.isEmpty)
    }

    func testBoundExtractorWithoutCopyAuthorizationFailsClosed() async {
        let shortcut = ShortcutStub()
        let frame = ScreenRectangle(x: 0, y: 0, width: 100, height: 100)
        let context = BoundSelectionContext(
            activation: GridActivation(generation: 1),
            sessionIdentity: SelectionSessionIdentity(rawValue: 1),
            source: SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 7),
            sourceWindowFrame: frame,
            element: SelectionElementIdentity(rawValue: 5),
            anchor: GridBoundary(row: 0, column: 0),
            sourceRange: 0..<0,
            display: DisplayGeometry(
                displayID: 7,
                appKitFrame: frame,
                coreGraphicsBounds: frame,
                backingScale: 2
            )
        )
        let clipboard = ClipboardStub()
        let coordinator = makeCoordinator(
            shortcut: shortcut,
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(result: .boundConfirmed(rectangle, context)),
            extractor: BoundWithoutAuthorizationExtractorStub(),
            clipboard: clipboard,
            states: StateRecorder()
        )
        XCTAssertTrue(coordinator.installShortcut())

        XCTAssertTrue(shortcut.trigger())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .failed(.extractionFailed))
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
    }

    func testCopyAuthorizationCancellationFinishesAsCancelledWithoutWriting() async {
        let clipboard = ClipboardStub()
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(result: .confirmed(rectangle)),
            extractor: CopyAuthorizationCancellationExtractorStub(),
            clipboard: clipboard,
            states: StateRecorder()
        )

        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .cancelled)
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

    func testPermissionRevokedAfterExtractionPreventsClipboardWrite() async {
        let permission = PermissionStub(status: .granted)
        let extractor = ControlledExtractorStub()
        let clipboard = ClipboardStub()
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: permission,
            overlay: ImmediateOverlayStub(result: .confirmed(rectangle)),
            extractor: extractor,
            clipboard: clipboard,
            states: StateRecorder()
        )
        XCTAssertTrue(coordinator.activate())
        guard await extractor.waitUntilStarted() else {
            return XCTFail("Extraction did not start")
        }

        permission.selectionPermissionStatus = .required
        await extractor.succeed(with: "must not copy")
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .permissionRequired)
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
    }

    func testOverlayKeepsCopyOwnershipAndConsumesRepeatsUntilSuccess() async {
        let overlay = CopyOwningOverlayStub()
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
        guard await overlay.waitUntilPresented() else {
            return XCTFail("Copy-owning overlay did not present")
        }
        overlay.pressCopy(rectangle)
        guard await extractor.waitUntilStarted() else {
            return XCTFail("Extraction did not start")
        }

        overlay.pressCopy(rectangle)
        XCTAssertTrue(overlay.isPresented)
        XCTAssertEqual(overlay.copyInvocationCount, 1)
        XCTAssertEqual(overlay.consumedRepeatCount, 1)
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)

        await extractor.succeed(with: "selected")
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .completed)
        XCTAssertEqual(clipboard.writtenTexts, ["selected"])
        XCTAssertFalse(overlay.isPresented)
        XCTAssertEqual(overlay.dismissalCount, 1)
    }

    func testEscapeDuringRetainedCopyRejectsLateExtractionResult() async {
        let overlay = CopyOwningOverlayStub()
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
        guard await overlay.waitUntilPresented() else {
            return XCTFail("Copy-owning overlay did not present")
        }
        overlay.pressCopy(rectangle)
        guard await extractor.waitUntilStarted() else {
            return XCTFail("Extraction did not start")
        }

        overlay.pressEscape()
        await coordinator.waitForMostRecentSession()
        XCTAssertEqual(coordinator.state, .cancelled)
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)

        await extractor.succeed(with: "stale result")
        guard await overlay.waitUntilCopyTaskFinished() else {
            return XCTFail("Cancelled copy task did not finish")
        }
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
    }

    func testSecureInputEnabledAtCopyAuthorizationPreventsClipboardWrite() async {
        let clipboard = ClipboardStub()
        let coordinator = makeCoordinator(
            shortcut: ShortcutStub(),
            permission: PermissionStub(status: .granted),
            overlay: ImmediateOverlayStub(result: .confirmed(rectangle)),
            extractor: CopyAuthorizationExtractorStub(),
            clipboard: clipboard,
            states: StateRecorder()
        )

        XCTAssertTrue(coordinator.activate())
        await coordinator.waitForMostRecentSession()

        XCTAssertEqual(coordinator.state, .failed(.secureInputUnsupported))
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
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

    func testEscapeDuringCopyAuthorizationRejectsLateAuthorization() async {
        let overlay = CopyOwningOverlayStub()
        let extractor = ControlledAuthorizationExtractorStub()
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
        guard await overlay.waitUntilPresented() else {
            return XCTFail("Copy-owning overlay did not present")
        }
        overlay.pressCopy(rectangle)
        guard await extractor.waitUntilAuthorizationStarted() else {
            return XCTFail("Copy authorization did not start")
        }

        overlay.pressEscape()
        await extractor.succeedAuthorization()
        guard await overlay.waitUntilCopyTaskFinished() else {
            return XCTFail("Cancelled authorization task did not finish")
        }
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
        XCTAssertEqual(shortcut.cancelledActivations, [])
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

    func triggerSourceCaptureFailure(_ failure: SelectionSourceFailure) {
        nextGeneration += 1
        handler?(
            .sourceCaptureFailed(
                GridActivation(generation: nextGeneration),
                failure
            )
        )
    }

    private func testSourceContext(generation: UInt64) -> ActivationSourceContext {
        ActivationSourceContext(
            activation: GridActivation(generation: generation),
            sessionIdentity: SelectionSessionIdentity(rawValue: generation),
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
        sourceContext: ActivationSourceContext?,
        onReady: @escaping @MainActor @Sendable () -> [GridHandoffCommand]?,
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void,
        onCopyRequested: @escaping @MainActor @Sendable (
            SelectionCopyRequest
        ) async -> SelectionCopyResult
    ) async throws -> SelectionOverlayResult {
        guard onReady() != nil else {
            return .cancelled
        }
        return await resolveTestCopy(
            try await select(onDrag: onDrag),
            onCopyRequested: onCopyRequested
        )
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
private final class CopyOwningOverlayStub: SelectionOverlayPresenting {
    private var continuation: CheckedContinuation<SelectionOverlayResult, any Error>?
    private var copyHandler: (@MainActor @Sendable (
        SelectionCopyRequest
    ) async -> SelectionCopyResult)?
    private var copyTask: Task<Void, Never>?
    private var presentationWaiters: [XCTestExpectation] = []
    private var copyCompletionWaiters: [XCTestExpectation] = []
    private(set) var copyInvocationCount = 0
    private(set) var consumedRepeatCount = 0
    private(set) var dismissalCount = 0

    var isPresented: Bool {
        continuation != nil
    }

    func select(
        sourceContext: ActivationSourceContext?,
        onReady: @escaping @MainActor @Sendable () -> [GridHandoffCommand]?,
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void,
        onCopyRequested: @escaping @MainActor @Sendable (
            SelectionCopyRequest
        ) async -> SelectionCopyResult
    ) async throws -> SelectionOverlayResult {
        guard onReady() != nil else {
            return .cancelled
        }
        copyHandler = onCopyRequested
        presentationWaiters.forEach { $0.fulfill() }
        presentationWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func select(
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult {
        .cancelled
    }

    func dismissSelection() {
        dismissalCount += 1
        copyTask?.cancel()
        copyHandler = nil
        resolve(.cancelled)
    }

    func pressCopy(_ rectangle: SelectionRectangle) {
        guard copyTask == nil else {
            consumedRepeatCount += 1
            return
        }
        guard let copyHandler else {
            return
        }
        copyInvocationCount += 1
        copyTask = Task { @MainActor [weak self] in
            let result = await copyHandler(.unbound(rectangle))
            guard let self else {
                return
            }
            defer {
                self.copyTask = nil
                self.copyCompletionWaiters.forEach { $0.fulfill() }
                self.copyCompletionWaiters.removeAll()
            }
            guard !Task.isCancelled else {
                return
            }
            self.resolve(.copyFinished(result))
        }
    }

    func pressEscape() {
        copyTask?.cancel()
        resolve(.cancelled)
    }

    func waitUntilPresented(timeout: TimeInterval = 2) async -> Bool {
        guard !isPresented else {
            return true
        }
        let expectation = XCTestExpectation(description: "Overlay presents")
        presentationWaiters.append(expectation)
        let result = await XCTWaiter().fulfillment(
            of: [expectation],
            timeout: timeout
        )
        presentationWaiters.removeAll { $0 === expectation }
        return result == .completed
    }

    func waitUntilCopyTaskFinished(timeout: TimeInterval = 2) async -> Bool {
        guard copyTask != nil else {
            return true
        }
        let expectation = XCTestExpectation(description: "Copy task finishes")
        copyCompletionWaiters.append(expectation)
        let result = await XCTWaiter().fulfillment(
            of: [expectation],
            timeout: timeout
        )
        copyCompletionWaiters.removeAll { $0 === expectation }
        return result == .completed
    }

    private func resolve(_ result: SelectionOverlayResult) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        continuation.resume(returning: result)
    }
}

@MainActor
private final class HandoffCapturingOverlayStub: SelectionOverlayPresenting {
    private(set) var handoffCommands: [GridHandoffCommand]?
    private(set) var sourceContext: ActivationSourceContext?

    func select(
        sourceContext: ActivationSourceContext?,
        onReady: @escaping @MainActor @Sendable () -> [GridHandoffCommand]?,
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void,
        onCopyRequested: @escaping @MainActor @Sendable (
            SelectionCopyRequest
        ) async -> SelectionCopyResult
    ) async throws -> SelectionOverlayResult {
        try await select(
            sourceContext: sourceContext,
            onReady: onReady,
            onDrag: onDrag
        )
    }

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
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void,
        onCopyRequested: @escaping @MainActor @Sendable (
            SelectionCopyRequest
        ) async -> SelectionCopyResult
    ) async throws -> SelectionOverlayResult {
        throw TestFailure.expected
    }

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
        sourceContext: ActivationSourceContext?,
        onReady: @escaping @MainActor @Sendable () -> [GridHandoffCommand]?,
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void,
        onCopyRequested: @escaping @MainActor @Sendable (
            SelectionCopyRequest
        ) async -> SelectionCopyResult
    ) async throws -> SelectionOverlayResult {
        guard onReady() != nil else {
            return .cancelled
        }
        return try await select(onDrag: onDrag)
    }

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

@MainActor
private func resolveTestCopy(
    _ result: SelectionOverlayResult,
    onCopyRequested: @escaping @MainActor @Sendable (
        SelectionCopyRequest
    ) async -> SelectionCopyResult
) async -> SelectionOverlayResult {
    switch result {
    case let .confirmed(rectangle):
        return .copyFinished(await onCopyRequested(.unbound(rectangle)))
    case let .boundConfirmed(rectangle, context):
        let selection = GridIndexSelection(
            anchor: GridBoundary(row: 0, column: 0),
            focus: GridBoundary(row: 0, column: 1)
        )
        return .copyFinished(
            await onCopyRequested(
                .bound(
                    rectangle,
                    context,
                    GridCopyAuthorization(
                        activation: context.activation,
                        sequence: 1,
                        selection: selection
                    )
                )
            )
        )
    case .copyFinished, .cancelled, .sourceFailed:
        return result
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

private actor ControlledAuthorizationExtractorStub: RectangularTextExtracting {
    private var startedExpectations: [XCTestExpectation] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var authorizationStarted = false
    private var authorizationShouldSucceed = false

    func extractText(in rectangle: SelectionRectangle) async throws -> String {
        "selected"
    }

    func validateCopyAuthorization(
        for boundContext: BoundSelectionContext?
    ) async throws {
        authorizationStarted = true
        startedExpectations.forEach { $0.fulfill() }
        startedExpectations.removeAll()
        if authorizationShouldSucceed {
            authorizationShouldSucceed = false
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilAuthorizationStarted(timeout: TimeInterval = 2) async -> Bool {
        guard !authorizationStarted else {
            return true
        }
        let expectation = XCTestExpectation(description: "Copy authorization starts")
        startedExpectations.append(expectation)
        let result = await XCTWaiter().fulfillment(
            of: [expectation],
            timeout: timeout
        )
        startedExpectations.removeAll { $0 === expectation }
        return result == .completed
    }

    func succeedAuthorization() {
        guard let continuation else {
            authorizationShouldSucceed = true
            return
        }
        continuation.resume()
        continuation = nil
    }
}

private actor BoundExtractorStub: RectangularTextExtracting {
    private let text: String
    private var unboundCallCount = 0
    private var boundContexts: [BoundSelectionContext] = []
    private var authorizedContexts: [BoundSelectionContext?] = []
    private var discardedSessions: [SelectionSessionIdentity] = []

    init(text: String) {
        self.text = text
    }

    func extractText(in rectangle: SelectionRectangle) async throws -> String {
        unboundCallCount += 1
        return text
    }

    func extractText(
        in rectangle: SelectionRectangle,
        boundContext: BoundSelectionContext
    ) async throws -> String {
        boundContexts.append(boundContext)
        return text
    }

    func discardBoundContexts(for sessionIdentity: SelectionSessionIdentity) async {
        discardedSessions.append(sessionIdentity)
    }

    func validateCopyAuthorization(
        for boundContext: BoundSelectionContext?
    ) async throws {
        authorizedContexts.append(boundContext)
    }

    func calls() -> (
        unbound: Int,
        bound: [BoundSelectionContext],
        authorized: [BoundSelectionContext?],
        discarded: [SelectionSessionIdentity]
    ) {
        (unboundCallCount, boundContexts, authorizedContexts, discardedSessions)
    }
}

private actor CopyAuthorizationCancellationExtractorStub: RectangularTextExtracting {
    func extractText(in rectangle: SelectionRectangle) async throws -> String {
        "text"
    }

    func validateCopyAuthorization(
        for boundContext: BoundSelectionContext?
    ) async throws {
        throw CancellationError()
    }
}

private actor CopyAuthorizationExtractorStub: RectangularTextExtracting {
    func extractText(in rectangle: SelectionRectangle) async throws -> String {
        "must not copy"
    }

    func validateCopyAuthorization(
        for boundContext: BoundSelectionContext?
    ) async throws {
        throw SelectionSourceFailureError(.secureInputUnsupported)
    }
}

private actor BoundWithoutAuthorizationExtractorStub: RectangularTextExtracting {
    func extractText(in rectangle: SelectionRectangle) async throws -> String {
        "text"
    }

    func extractText(
        in rectangle: SelectionRectangle,
        boundContext: BoundSelectionContext
    ) async throws -> String {
        "text"
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
