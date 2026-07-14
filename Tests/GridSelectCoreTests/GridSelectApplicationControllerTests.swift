@testable import GridSelect
@testable import GridSelectCore
import XCTest

@MainActor
final class GridSelectApplicationControllerTests: XCTestCase {
    func testManualSourcePrefersLastExternalApplicationWhenGridSelectIsFrontmost() {
        XCTAssertEqual(
            MacOSActivationSourceCapturer.preferredSourceProcessIdentifier(
                frontmost: 100,
                current: 100,
                lastExternal: 42
            ),
            42
        )
    }

    func testManualSourceDoesNotReuseSelfOrInvalidCachedProcess() {
        XCTAssertNil(
            MacOSActivationSourceCapturer.preferredSourceProcessIdentifier(
                frontmost: 100,
                current: 100,
                lastExternal: 100
            )
        )
        XCTAssertNil(
            MacOSActivationSourceCapturer.preferredSourceProcessIdentifier(
                frontmost: 100,
                current: 100,
                lastExternal: 0
            )
        )
    }

    func testShortcutRejectsUnboundConfirmationBeforeExtractionOrCopy() async {
        let shortcut = ApplicationShortcutStub()
        let clipboard = ApplicationClipboardStub()
        let permissionSetup = ApplicationPermissionSetupPresenterStub()
        let rectangle = SelectionRectangle(displayID: 1, x: 10, y: 20, width: 30, height: 40)
        let controller = GridSelectApplicationController(
            shortcut: shortcut,
            permissionChecker: ApplicationPermissionStub(status: .granted),
            permissionSetupPresenter: permissionSetup,
            overlay: ApplicationOverlayStub(result: .confirmed(rectangle)),
            extractor: ApplicationExtractorStub(text: "alpha  \r\nbravo  \r\n"),
            clipboard: clipboard
        )

        XCTAssertTrue(controller.start())
        XCTAssertTrue(shortcut.trigger())
        await waitForTerminalState(controller)

        XCTAssertTrue(clipboard.values.isEmpty)
        XCTAssertEqual(
            controller.statusModel.snapshot.selectionState,
            .failed(.extractionFailed)
        )
        XCTAssertEqual(controller.statusModel.snapshot.statusTitle, "Text could not be read")
        XCTAssertEqual(
            controller.statusModel.snapshot.shortcutStatus,
            .active(displayName: "Double-Shift")
        )
        XCTAssertEqual(permissionSetup.presentationCount, 0)
    }

    func testUnboundShortcutNeverAttemptsFailingPasteboard() async {
        let shortcut = ApplicationShortcutStub()
        let clipboard = ApplicationClipboardStub()
        clipboard.shouldFail = true
        let rectangle = SelectionRectangle(displayID: 1, x: 10, y: 20, width: 30, height: 40)
        let controller = GridSelectApplicationController(
            shortcut: shortcut,
            permissionChecker: ApplicationPermissionStub(status: .granted),
            overlay: ApplicationOverlayStub(result: .confirmed(rectangle)),
            extractor: ApplicationExtractorStub(text: "selected"),
            clipboard: clipboard
        )

        XCTAssertTrue(controller.start())
        XCTAssertTrue(shortcut.trigger())
        await waitForTerminalState(controller)

        XCTAssertEqual(
            controller.statusModel.snapshot.selectionState,
            .failed(.extractionFailed)
        )
        XCTAssertEqual(controller.statusModel.snapshot.statusTitle, "Text could not be read")
        XCTAssertTrue(clipboard.values.isEmpty)
    }

    func testShortcutCancellationSkipsExtractionAndClipboard() async {
        let shortcut = ApplicationShortcutStub()
        let extractor = ApplicationExtractorStub(text: "unused")
        let clipboard = ApplicationClipboardStub()
        let controller = GridSelectApplicationController(
            shortcut: shortcut,
            permissionChecker: ApplicationPermissionStub(status: .granted),
            overlay: ApplicationOverlayStub(result: .cancelled),
            extractor: extractor,
            clipboard: clipboard
        )

        XCTAssertTrue(controller.start())
        XCTAssertTrue(shortcut.trigger())
        await waitForTerminalState(controller)

        XCTAssertEqual(controller.statusModel.snapshot.selectionState, .cancelled)
        let extractionCallCount = await extractor.callCount()
        XCTAssertEqual(extractionCallCount, 0)
        XCTAssertTrue(clipboard.values.isEmpty)
    }

    func testShortcutExtractionFailureSkipsClipboardAndSurfacesStatus() async {
        let shortcut = ApplicationShortcutStub()
        let extractor = ApplicationExtractorStub(shouldFail: true)
        let clipboard = ApplicationClipboardStub()
        let rectangle = SelectionRectangle(displayID: 1, x: 10, y: 20, width: 30, height: 40)
        let frame = ScreenRectangle(x: 0, y: 0, width: 100, height: 100)
        let display = DisplayGeometry(
            displayID: 1,
            appKitFrame: frame,
            coreGraphicsBounds: frame,
            backingScale: 2
        )
        let boundContext = BoundSelectionContext(
            activation: GridActivation(generation: 1),
            sessionIdentity: SelectionSessionIdentity(rawValue: 1),
            source: SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 7),
            sourceWindowFrame: frame,
            element: SelectionElementIdentity(rawValue: 1),
            anchor: GridBoundary(row: 0, column: 0),
            sourceRange: 0..<0,
            display: display
        )
        let controller = GridSelectApplicationController(
            shortcut: shortcut,
            permissionChecker: ApplicationPermissionStub(status: .granted),
            overlay: ApplicationOverlayStub(
                result: .boundConfirmed(rectangle, boundContext)
            ),
            extractor: extractor,
            clipboard: clipboard
        )

        XCTAssertTrue(controller.start())
        XCTAssertTrue(shortcut.trigger())
        await waitForTerminalState(controller)

        XCTAssertEqual(
            controller.statusModel.snapshot.selectionState,
            .failed(.extractionFailed)
        )
        XCTAssertEqual(controller.statusModel.snapshot.statusTitle, "Text could not be read")
        let extractionCallCount = await extractor.callCount()
        XCTAssertEqual(extractionCallCount, 1)
        XCTAssertTrue(clipboard.values.isEmpty)
    }

    func testMissingPermissionBlocksOverlayFromShortcut() async {
        let shortcut = ApplicationShortcutStub()
        let overlay = ApplicationOverlayStub(result: .cancelled)
        let permissionSetup = ApplicationPermissionSetupPresenterStub()
        let controller = GridSelectApplicationController(
            shortcut: shortcut,
            permissionChecker: ApplicationPermissionStub(status: .required),
            permissionSetupPresenter: permissionSetup,
            overlay: overlay,
            extractor: ApplicationExtractorStub(text: "unused"),
            clipboard: ApplicationClipboardStub()
        )

        XCTAssertTrue(controller.start())
        XCTAssertTrue(shortcut.trigger())
        await waitForTerminalState(controller)

        XCTAssertEqual(controller.statusModel.snapshot.selectionState, .permissionRequired)
        XCTAssertEqual(overlay.selectionCount, 0)
        XCTAssertEqual(permissionSetup.presentationCount, 1)
    }

    func testRevokedPermissionSynchronizesStatusOnNextShortcut() async {
        let shortcut = ApplicationShortcutStub()
        let permission = ApplicationPermissionStub(status: .granted)
        let overlay = ApplicationOverlayStub(result: .cancelled)
        let permissionSetup = ApplicationPermissionSetupPresenterStub()
        let controller = GridSelectApplicationController(
            shortcut: shortcut,
            permissionChecker: permission,
            permissionSetupPresenter: permissionSetup,
            overlay: overlay,
            extractor: ApplicationExtractorStub(text: "unused"),
            clipboard: ApplicationClipboardStub()
        )

        XCTAssertTrue(controller.start())
        XCTAssertEqual(controller.statusModel.snapshot.permissionStatus, .granted)
        permission.selectionPermissionStatus = .required
        XCTAssertTrue(shortcut.trigger())
        await waitForTerminalState(controller)

        XCTAssertEqual(controller.statusModel.snapshot.selectionState, .permissionRequired)
        XCTAssertEqual(controller.statusModel.snapshot.permissionStatus, .required)
        XCTAssertEqual(overlay.selectionCount, 0)
        XCTAssertEqual(permissionSetup.presentationCount, 1)
    }

    func testShortcutRegistrationFailureIsSurfaced() {
        let shortcut = ApplicationShortcutStub()
        shortcut.shouldFail = true
        let controller = GridSelectApplicationController(
            shortcut: shortcut,
            permissionChecker: ApplicationPermissionStub(status: .granted),
            overlay: ApplicationOverlayStub(result: .cancelled),
            extractor: ApplicationExtractorStub(text: "unused"),
            clipboard: ApplicationClipboardStub()
        )

        XCTAssertFalse(controller.start())
        XCTAssertEqual(
            controller.statusModel.snapshot.shortcutStatus,
            .registrationFailed(displayName: "Double-Shift")
        )
        XCTAssertEqual(controller.statusModel.snapshot.statusTitle, "Shortcut unavailable")
    }

    func testManualCaptureFailureSurfacesActionableStatus() {
        let controller = GridSelectApplicationController(
            shortcut: ApplicationShortcutStub(),
            permissionChecker: ApplicationPermissionStub(status: .granted),
            overlay: ApplicationOverlayStub(result: .cancelled),
            extractor: ApplicationExtractorStub(text: "unused"),
            clipboard: ApplicationClipboardStub()
        )
        let frame = ScreenRectangle(x: 0, y: 0, width: 100, height: 100)
        let context = ActivationSourceContext(
            activation: GridActivation(generation: 1),
            sessionIdentity: SelectionSessionIdentity(rawValue: 1),
            source: SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 7),
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

        XCTAssertFalse(
            controller.handleManualCaptureResult(
                .rejected(.secureInputUnsupported),
                sourceContext: context
            )
        )
        XCTAssertEqual(
            controller.statusModel.snapshot.selectionState,
            .failed(.secureInputUnsupported)
        )
        XCTAssertEqual(
            controller.statusModel.snapshot.statusTitle,
            "Secure input is unsupported"
        )
    }

    func testCancelStopsPendingManualCaptureBeforeOverlayStarts() async {
        let overlay = ApplicationOverlayStub(result: .cancelled)
        let controller = GridSelectApplicationController(
            shortcut: ApplicationShortcutStub(),
            permissionChecker: ApplicationPermissionStub(status: .granted),
            overlay: overlay,
            extractor: ApplicationExtractorStub(text: "unused"),
            clipboard: ApplicationClipboardStub()
        )
        let frame = ScreenRectangle(x: 0, y: 0, width: 100, height: 100)
        let context = ActivationSourceContext(
            activation: GridActivation(generation: 2),
            sessionIdentity: SelectionSessionIdentity(rawValue: 2),
            source: SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 7),
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
        XCTAssertTrue(
            controller.beginManualCapture(sourceContext: context) {
                try? await Task.sleep(for: .seconds(10))
                return .unavailable
            }
        )

        XCTAssertTrue(controller.cancelSelection())
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(overlay.selectionCount, 0)
    }

    func testListenerDisableMarksShortcutInactive() {
        let shortcut = ApplicationShortcutStub()
        let controller = GridSelectApplicationController(
            shortcut: shortcut,
            permissionChecker: ApplicationPermissionStub(status: .granted),
            overlay: ApplicationOverlayStub(result: .cancelled),
            extractor: ApplicationExtractorStub(text: "unused"),
            clipboard: ApplicationClipboardStub()
        )

        XCTAssertTrue(controller.start())
        shortcut.triggerListenerDisabled()

        XCTAssertEqual(
            controller.statusModel.snapshot.shortcutStatus,
            .inactive(displayName: "Double-Shift")
        )
        XCTAssertEqual(
            controller.statusModel.snapshot.selectionState,
            .failed(.listenerDisabled)
        )
    }

    private func waitForTerminalState(_ controller: GridSelectApplicationController) async {
        for _ in 0..<100 where controller.statusModel.snapshot.selectionState.isActive {
            await Task.yield()
        }
    }
}

private enum ApplicationTestError: Error {
    case expected
}

@MainActor
private final class ApplicationShortcutStub: SelectionShortcutRegistering {
    var shouldFail = false
    private var handler: (@MainActor @Sendable (SelectionShortcutEvent) -> Void)?
    private var nextGeneration: UInt64 = 0

    func registerEventHandler(
        _ handler: @escaping @MainActor @Sendable (SelectionShortcutEvent) -> Void
    ) throws {
        if shouldFail { throw ApplicationTestError.expected }
        self.handler = handler
    }

    func unregister() {
        handler = nil
    }

    func trigger() -> Bool {
        guard let handler else { return false }
        nextGeneration += 1
        handler(.activated(testSourceContext(generation: nextGeneration)))
        return true
    }

    func triggerListenerDisabled() {
        handler?(.listenerDisabled)
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
private final class ApplicationPermissionStub: SelectionPermissionChecking {
    var selectionPermissionStatus: SelectionPermissionStatus

    init(status: SelectionPermissionStatus) {
        selectionPermissionStatus = status
    }
}

@MainActor
private final class ApplicationPermissionSetupPresenterStub: PermissionSetupPresenting {
    private(set) var presentationCount = 0

    func presentPermissionSetup() {
        presentationCount += 1
    }
}

@MainActor
private final class ApplicationOverlayStub: SelectionOverlayPresenting {
    let result: SelectionOverlayResult
    private(set) var selectionCount = 0

    init(result: SelectionOverlayResult) {
        self.result = result
    }

    func select(
        onDrag: @escaping @MainActor @Sendable (SelectionRectangle) -> Void
    ) async throws -> SelectionOverlayResult {
        selectionCount += 1
        return result
    }

    func dismissSelection() {}
}

private actor ApplicationExtractorStub: RectangularTextExtracting {
    private let text: String
    private let shouldFail: Bool
    private var calls = 0

    init(text: String) {
        self.text = text
        shouldFail = false
    }

    init(shouldFail: Bool) {
        text = ""
        self.shouldFail = shouldFail
    }

    func extractText(in rectangle: SelectionRectangle) async throws -> String {
        calls += 1
        if shouldFail { throw ApplicationTestError.expected }
        return text
    }

    func extractText(
        in rectangle: SelectionRectangle,
        boundContext: BoundSelectionContext
    ) async throws -> String {
        try await extractText(in: rectangle)
    }

    func validateCopyAuthorization(for boundContext: BoundSelectionContext?) async throws {}

    func callCount() -> Int { calls }
}

@MainActor
private final class ApplicationClipboardStub: ClipboardWriting {
    var shouldFail = false
    private(set) var values: [String] = []

    func writePlainText(_ text: String) throws {
        if shouldFail { throw ApplicationTestError.expected }
        values.append(text)
    }
}
