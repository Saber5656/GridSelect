@testable import GridSelect
import ApplicationServices
import Foundation
import GridSelectCore
import XCTest

final class MacOSAccessibilityExtractionEngineTests: XCTestCase {
    func testSecureHitTargetStopsBeforeAncestorTextCalls() {
        let client = FakeAccessibilityClient()
        let secure = client.addElement("secure", pid: 10, role: "AXSecureTextField")
        let parent = client.addElement("parent", pid: 10)
        client.setParent(parent, for: secure)
        client.configureMonospace(parent, lines: ["secret"])
        client.hitTested = secure

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .secureTextElement)
        }
        XCTAssertEqual(client.textReadCount, 0)
        XCTAssertEqual(client.boundsReadCount, 0)
    }

    func testSecureAncestorStopsBeforeReadableChildTextCalls() {
        let client = FakeAccessibilityClient()
        let child = client.addElement("child", pid: 10)
        let secureParent = client.addElement("secure-parent", pid: 10, role: "AXSecureTextField")
        client.setParent(secureParent, for: child)
        client.configureMonospace(child, lines: ["secret"])
        client.hitTested = child

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .secureTextElement)
        }
        XCTAssertEqual(client.textReadCount, 0)
        XCTAssertEqual(client.boundsReadCount, 0)
    }

    func testSecureDescendantStopsReadableContainerBeforeTextCalls() {
        let client = FakeAccessibilityClient()
        let container = client.addElement("container", pid: 10)
        let secureChild = client.addElement(
            "secure-child",
            pid: 10,
            role: "AXSecureTextField"
        )
        client.setParent(container, for: secureChild)
        client.configureMonospace(container, lines: ["aggregate secret"])
        client.hitTested = container

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .secureTextElement)
        }
        XCTAssertEqual(client.textReadCount, 0)
        XCTAssertEqual(client.boundsReadCount, 0)
    }

    func testCanonicalSecureSubroleStopsBeforeTextCalls() {
        let client = FakeAccessibilityClient()
        let hit = client.addElement(
            "hit",
            pid: 10,
            role: "AXTextField",
            subrole: kAXSecureTextFieldSubrole as String
        )
        client.configureMonospace(hit, lines: ["secret"])
        client.hitTested = hit

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .secureTextElement)
        }
        XCTAssertEqual(client.textReadCount, 0)
        XCTAssertEqual(client.boundsReadCount, 0)
    }

    func testHitTestedTargetWinsOverFocusedElementFromDifferentPID() throws {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        let focused = client.addElement(
            "focused",
            pid: 20,
            frame: CGRect(x: 80, y: 40, width: 300, height: 200)
        )
        client.configureMonospace(hit, lines: ["hit text"])
        client.configureMonospace(focused, lines: ["wrong app"])
        client.hitTested = hit
        client.focused = focused

        let output = try engine(client).extract(rectangle: selection, display: display)

        XCTAssertEqual(output, "hit ")
        XCTAssertEqual(client.textReadsByElement["focused", default: 0], 0)
    }

    func testFocusedFallbackRequiresFrameContainmentWhenHitTestIsUnavailable() {
        let client = FakeAccessibilityClient()
        let focused = client.addElement(
            "focused",
            pid: 10,
            frame: CGRect(x: 700, y: 700, width: 100, height: 100)
        )
        client.configureMonospace(focused, lines: ["outside"])
        client.focused = focused

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .targetMismatch)
        }
        XCTAssertEqual(client.textReadCount, 0)
    }

    func testEmptyLeafContinuesToSupportedAncestor() throws {
        let client = FakeAccessibilityClient()
        let leaf = client.addElement("leaf", pid: 10)
        let parent = client.addElement("parent", pid: 10)
        client.setParent(parent, for: leaf)
        client.configureMonospace(leaf, lines: ["offscreen"], originX: 500)
        client.configureMonospace(parent, lines: ["ancestor"])
        client.hitTested = leaf

        let output = try engine(client).extract(rectangle: selection, display: display)

        XCTAssertEqual(output, "ance")
        XCTAssertGreaterThan(client.textReadsByElement["parent", default: 0], 0)
    }

    func testMissingAncestorPIDStopsWalkWithoutDiscardingLeaf() throws {
        let client = FakeAccessibilityClient()
        let leaf = client.addElement("leaf", pid: 10)
        let parent = client.addElement("parent", pid: 10)
        client.setParent(parent, for: leaf)
        client.configureMonospace(leaf, lines: ["leaf text"])
        client.pidUnavailableIDs.insert("parent")
        client.hitTested = leaf

        try XCTAssertEqual(
            try engine(client).extract(rectangle: selection, display: display),
            "leaf"
        )
    }

    func testSecureAncestorWithMissingPIDStillRejectsBeforeTextCalls() {
        let client = FakeAccessibilityClient()
        let leaf = client.addElement("leaf", pid: 10)
        let parent = client.addElement(
            "parent",
            pid: 10,
            role: "AXTextField",
            subrole: kAXSecureTextFieldSubrole as String
        )
        client.setParent(parent, for: leaf)
        client.configureMonospace(leaf, lines: ["secret"])
        client.pidUnavailableIDs.insert("parent")
        client.hitTested = leaf

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .secureTextElement)
        }
        XCTAssertEqual(client.textReadCount, 0)
        XCTAssertEqual(client.boundsReadCount, 0)
    }

    func testVisibleRangeStartingMidLineKeepsPartialFirstLine() throws {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(hit, lines: ["abcdef"])
        client.elements["hit"]?.visibleRange = CFRange(location: 2, length: 3)
        client.hitTested = hit
        let partialSelection = SelectionRectangle(
            displayID: 1,
            x: 120,
            y: 930,
            width: 30,
            height: 20
        )

        try XCTAssertEqual(
            try engine(client).extract(rectangle: partialSelection, display: display),
            "cde"
        )
    }

    func testVisibleRangeStartingMidLineAlignsFollowingRows() throws {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(hit, lines: ["abcdef", "uvwxyz"])
        client.elements["hit"]?.visibleRange = CFRange(location: 2, length: 11)
        client.hitTested = hit
        let twoRowSelection = SelectionRectangle(
            displayID: 1,
            x: 120,
            y: 910,
            width: 30,
            height: 40
        )

        try XCTAssertEqual(
            try engine(client).extract(rectangle: twoRowSelection, display: display),
            "cde\nwxy"
        )
        let prefixSelection = SelectionRectangle(
            displayID: 1,
            x: 100,
            y: 910,
            width: 20,
            height: 40
        )
        try XCTAssertEqual(
            try engine(client).extract(rectangle: prefixSelection, display: display),
            "  \nuv"
        )
    }

    func testWholeLineBoundsProvideCharacterWidthFallback() throws {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(hit, lines: ["abcdef"])
        client.supportsSingleCharacterBounds = false
        client.hitTested = hit

        try XCTAssertEqual(
            try engine(client).extract(rectangle: selection, display: display),
            "abcd"
        )
    }

    func testMultipleGlyphSamplesRejectProportionalText() {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(
            hit,
            lines: ["iWi"],
            characterWidths: ["i": 4, "W": 12]
        )
        client.hitTested = hit

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .unstableGeometry)
        }
    }

    func testHugeLineNumbersAreRejectedBeforeEnumeration() {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(hit, lines: ["abc"])
        client.forcedLineNumbers = (first: 0, last: Int.max)
        client.hitTested = hit

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .resourceLimitExceeded)
        }
    }

    func testOverflowingAXRangeIsRejected() {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(hit, lines: ["abc"])
        client.elements["hit"]?.visibleRange = CFRange(location: Int.max - 1, length: 10)
        client.hitTested = hit

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .resourceLimitExceeded)
        }
    }

    func testCallBudgetStopsPathologicalTargets() {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(hit, lines: ["abc"])
        client.hitTested = hit
        let limits = AccessibilityExtractionLimits(maximumAXCalls: 3)

        XCTAssertThrowsError(
            try MacOSAccessibilityExtractionEngine(client: client, limits: limits)
                .extract(rectangle: selection, display: display)
        ) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .resourceLimitExceeded)
        }
    }

    func testOversizedChildListFailsBeforeTextRead() {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(hit, lines: ["must not read"])
        client.hitTested = hit
        client.forcedChildCount = 1_000

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .resourceLimitExceeded)
        }
        XCTAssertEqual(client.textReadCount, 0)
        XCTAssertEqual(client.boundsReadCount, 0)
    }

    func testOverlongAXStringResponseIsRejected() {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(hit, lines: ["abc"])
        client.forcedString = String(repeating: "x", count: 100)
        client.hitTested = hit

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .resourceLimitExceeded)
        }
        XCTAssertEqual(client.boundsReadCount, 0)
    }

    func testCallerCancellationStopsDetachedExtractionBeforeTextRead() async {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(hit, lines: ["abc"])
        client.hitTested = hit
        let enteredPreTextCall = DispatchSemaphore(value: 0)
        let releasePreTextCall = DispatchSemaphore(value: 0)
        client.parameterizedNamesBarrier = (enteredPreTextCall, releasePreTextCall)
        let extractor = MacOSAccessibilityTextExtractor(client: client)
        let selectedRectangle = selection
        let displayGeometry = display

        let extraction = Task {
            try await extractor.extractText(in: selectedRectangle, display: displayGeometry)
        }
        XCTAssertEqual(enteredPreTextCall.wait(timeout: .now() + 2), .success)
        extraction.cancel()
        releasePreTextCall.signal()

        do {
            _ = try await extraction.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        XCTAssertEqual(client.textReadCount, 0)
    }

    func testBoundExtractionRevalidatesFocusAfterSnapshot() async {
        let client = FakeAccessibilityClient()
        let original = client.addElement("original", pid: 10)
        let replacement = client.addElement("replacement", pid: 10)
        client.configureMonospace(original, lines: ["original"])
        client.configureMonospace(replacement, lines: ["replacement"])
        client.focused = original
        let enteredSnapshot = DispatchSemaphore(value: 0)
        let releaseSnapshot = DispatchSemaphore(value: 0)
        client.parameterizedNamesBarrier = (enteredSnapshot, releaseSnapshot)
        let extractionEngine = engine(client)
        let selectedRectangle = selection
        let displayGeometry = display

        let task = Task.detached {
            try extractionEngine.extract(
                rectangle: selectedRectangle,
                display: displayGeometry,
                from: original,
                requiredPID: 10
            )
        }
        XCTAssertEqual(enteredSnapshot.wait(timeout: .now() + 2), .success)
        client.focused = replacement
        releaseSnapshot.signal()

        do {
            _ = try await task.value
            XCTFail("Expected post-snapshot focus mismatch")
        } catch {
            XCTAssertEqual(error as? MacOSAccessibilityExtractionError, .targetMismatch)
        }
    }

    func testSecureDescendantAddedDuringSnapshotPreventsOutput() async {
        let client = FakeAccessibilityClient()
        let container = client.addElement("container", pid: 10)
        client.configureMonospace(container, lines: ["aggregate"])
        client.hitTested = container
        let enteredSnapshot = DispatchSemaphore(value: 0)
        let releaseSnapshot = DispatchSemaphore(value: 0)
        client.parameterizedNamesBarrier = (enteredSnapshot, releaseSnapshot)
        let extractionEngine = engine(client)
        let selectedRectangle = selection
        let displayGeometry = display

        let task = Task.detached {
            try extractionEngine.extract(
                rectangle: selectedRectangle,
                display: displayGeometry
            )
        }
        XCTAssertEqual(enteredSnapshot.wait(timeout: .now() + 2), .success)
        let secure = client.addElement(
            "late-secure",
            pid: 10,
            role: "AXSecureTextField"
        )
        client.setParent(container, for: secure)
        releaseSnapshot.signal()

        do {
            _ = try await task.value
            XCTFail("Expected secure descendant rejection")
        } catch {
            XCTAssertEqual(error as? MacOSAccessibilityExtractionError, .secureTextElement)
        }
    }

    @MainActor
    func testCaretBindingExtractsFromExactElementWithoutCopyTimeHitTest() async throws {
        let client = FakeAccessibilityClient()
        let original = client.addElement(
            "original",
            pid: 10,
            frame: CGRect(x: 80, y: 40, width: 300, height: 200)
        )
        let replacement = client.addElement(
            "replacement",
            pid: 10,
            frame: CGRect(x: 80, y: 40, width: 300, height: 200)
        )
        let axWindow = client.addElement(
            "window",
            pid: 10,
            frame: CGRect(x: 0, y: 0, width: 500, height: 500),
            role: kAXWindowRole as String
        )
        client.setWindow(axWindow, for: original)
        client.setWindow(axWindow, for: replacement)
        client.configureMonospace(original, lines: ["original"])
        client.configureMonospace(replacement, lines: ["replaced"])
        client.focused = original
        client.selectedRange = CFRange(location: 1, length: 0)
        let service = MacOSAccessibilitySelectionService(
            client: client,
            windowValidator: { _, _ in true },
            secureInputEnabled: { false }
        )
        let activation = GridActivation(generation: 7)
        let session = SelectionSessionIdentity(rawValue: 17)
        let source = SelectionSourceIdentity(processIdentifier: 10, windowIdentifier: 4)
        let window = ScreenRectangle(x: 0, y: 0, width: 500, height: 500)

        let caret: GridCaretCandidate
        switch service.captureCaretCandidate(
                activation: activation,
                sessionIdentity: session,
                source: source,
                sourceWindowFrame: window,
                displays: [display]
        ) {
        case let .captured(candidate):
            caret = candidate
        default:
            return XCTFail("Expected captured caret")
        }
        var binder = GridSelectionContextBinder(
            activationContext: ActivationSourceContext(
                activation: activation,
                sessionIdentity: session,
                source: source,
                sourceWindowFrame: window,
                displays: [display],
                caretCandidate: caret
            )
        )
        guard case let .bound(context) = binder.bindKeyboardCaret() else {
            return XCTFail("Expected bound caret")
        }
        client.hitTested = replacement

        let output = try await service.extractText(in: selection, boundContext: context)

        XCTAssertEqual(output, "orig")
        XCTAssertGreaterThan(client.textReadsByElement["original", default: 0], 0)
        XCTAssertEqual(client.textReadsByElement["replacement", default: 0], 0)
        XCTAssertEqual(client.hitTestCallCount, 0)

        client.focused = replacement
        do {
            try await service.validateCopyAuthorization(for: context)
            XCTFail("Expected authorization-time focus mismatch")
        } catch let error as SelectionSourceFailureError {
            XCTAssertEqual(error.failure, .sourceContextInvalid)
        }

        service.discardBoundContextsSynchronously(for: session)
        do {
            _ = try await service.extractText(in: selection, boundContext: context)
            XCTFail("Expected discarded context rejection")
        } catch let error as SelectionSourceFailureError {
            XCTAssertEqual(error.failure, .sourceContextInvalid)
        }
    }

    @MainActor
    func testBoundExtractionRejectsFocusChangeWithoutReadingReplacement() async throws {
        let client = FakeAccessibilityClient()
        let original = client.addElement("original", pid: 10)
        let replacement = client.addElement("replacement", pid: 10)
        let axWindow = client.addElement(
            "window",
            pid: 10,
            frame: CGRect(x: 0, y: 0, width: 500, height: 500),
            role: kAXWindowRole as String
        )
        client.setWindow(axWindow, for: original)
        client.setWindow(axWindow, for: replacement)
        client.configureMonospace(original, lines: ["original"])
        client.configureMonospace(replacement, lines: ["replacement"])
        client.focused = original
        client.selectedRange = CFRange(location: 1, length: 0)
        let service = MacOSAccessibilitySelectionService(
            client: client,
            windowValidator: { _, _ in true },
            secureInputEnabled: { false }
        )
        let activation = GridActivation(generation: 9)
        let session = SelectionSessionIdentity(rawValue: 19)
        let source = SelectionSourceIdentity(processIdentifier: 10, windowIdentifier: 4)
        let window = ScreenRectangle(x: 0, y: 0, width: 500, height: 500)
        let caret: GridCaretCandidate
        switch service.captureCaretCandidate(
                activation: activation,
                sessionIdentity: session,
                source: source,
                sourceWindowFrame: window,
                displays: [display]
        ) {
        case let .captured(candidate):
            caret = candidate
        default:
            return XCTFail("Expected captured caret")
        }
        var binder = GridSelectionContextBinder(
            activationContext: ActivationSourceContext(
                activation: activation,
                sessionIdentity: session,
                source: source,
                sourceWindowFrame: window,
                displays: [display],
                caretCandidate: caret
            )
        )
        guard case let .bound(context) = binder.bindKeyboardCaret() else {
            return XCTFail("Expected bound caret")
        }
        let readsBeforeExtraction = client.textReadCount
        client.focused = replacement

        do {
            _ = try await service.extractText(in: selection, boundContext: context)
            XCTFail("Expected focus mismatch")
        } catch let error as SelectionSourceFailureError {
            XCTAssertEqual(error.failure, .sourceContextInvalid)
        }
        XCTAssertEqual(client.textReadCount, readsBeforeExtraction)
        XCTAssertEqual(client.textReadsByElement["replacement", default: 0], 0)
    }

    @MainActor
    func testMouseBindingRejectsDifferentProcessBeforeTextRead() {
        let client = FakeAccessibilityClient()
        let foreign = client.addElement("foreign", pid: 20)
        client.configureMonospace(foreign, lines: ["foreign"])
        client.hitTested = foreign
        let service = MacOSAccessibilitySelectionService(
            client: client,
            windowValidator: { _, _ in true },
            secureInputEnabled: { false }
        )
        let context = ActivationSourceContext(
            activation: GridActivation(generation: 8),
            sessionIdentity: SelectionSessionIdentity(rawValue: 18),
            source: SelectionSourceIdentity(processIdentifier: 10, windowIdentifier: 4),
            sourceWindowFrame: ScreenRectangle(x: 0, y: 0, width: 500, height: 500),
            displays: [display],
            caretCandidate: nil
        )

        XCTAssertEqual(
            service.resolveMouseAnchor(
                at: SelectionPoint(x: 110, y: 940),
                sourceContext: context
            ),
            .rejected(.sourceContextInvalid)
        )
        XCTAssertEqual(client.textReadCount, 0)
    }

    @MainActor
    func testCaretAndMouseReuseExactElementIdentityWithinSession() {
        let client = FakeAccessibilityClient()
        let text = client.addElement("text", pid: 10)
        let axWindow = client.addElement(
            "window",
            pid: 10,
            frame: CGRect(x: 0, y: 0, width: 500, height: 500),
            role: kAXWindowRole as String
        )
        client.setWindow(axWindow, for: text)
        client.configureMonospace(text, lines: ["abcdef"])
        client.focused = text
        client.hitTested = text
        client.selectedRange = CFRange(location: 1, length: 0)
        let service = MacOSAccessibilitySelectionService(
            client: client,
            windowValidator: { _, _ in true },
            secureInputEnabled: { false }
        )
        let activation = GridActivation(generation: 10)
        let session = SelectionSessionIdentity(rawValue: 20)
        let source = SelectionSourceIdentity(processIdentifier: 10, windowIdentifier: 4)
        let window = ScreenRectangle(x: 0, y: 0, width: 500, height: 500)
        let caret: GridCaretCandidate
        switch service.captureCaretCandidate(
            activation: activation,
            sessionIdentity: session,
            source: source,
            sourceWindowFrame: window,
            displays: [display]
        ) {
        case let .captured(candidate):
            caret = candidate
        default:
            return XCTFail("Expected captured caret")
        }
        let context = ActivationSourceContext(
            activation: activation,
            sessionIdentity: session,
            source: source,
            sourceWindowFrame: window,
            displays: [display],
            caretCandidate: caret
        )

        guard case let .resolved(mouse) = service.resolveMouseAnchor(
            at: SelectionPoint(x: 110, y: 940),
            sourceContext: context
        ) else {
            return XCTFail("Expected mouse anchor")
        }
        XCTAssertEqual(mouse.element, caret.element)
        XCTAssertEqual(caret.sourceRange, 1..<1)
        XCTAssertEqual(mouse.sourceRange, 1..<1)
        XCTAssertEqual(service.registeredContextCount, 1)
    }

    @MainActor
    func testCaretAndMouseRejectTabsAsUnsupportedText() {
        let client = FakeAccessibilityClient()
        let text = client.addElement("text", pid: 10)
        let axWindow = client.addElement(
            "window",
            pid: 10,
            frame: CGRect(x: 0, y: 0, width: 500, height: 500),
            role: kAXWindowRole as String
        )
        client.setWindow(axWindow, for: text)
        client.configureMonospace(text, lines: ["a\tb"])
        client.focused = text
        client.hitTested = text
        client.selectedRange = CFRange(location: 1, length: 0)
        let service = MacOSAccessibilitySelectionService(
            client: client,
            windowValidator: { _, _ in true },
            secureInputEnabled: { false }
        )
        let activation = GridActivation(generation: 15)
        let session = SelectionSessionIdentity(rawValue: 25)
        let source = SelectionSourceIdentity(processIdentifier: 10, windowIdentifier: 4)
        let window = ScreenRectangle(x: 0, y: 0, width: 500, height: 500)

        switch service.captureCaretCandidate(
            activation: activation,
            sessionIdentity: session,
            source: source,
            sourceWindowFrame: window,
            displays: [display]
        ) {
        case .rejected(.unsupportedText):
            break
        default:
            XCTFail("Expected caret tab rejection")
        }

        let context = ActivationSourceContext(
            activation: activation,
            sessionIdentity: session,
            source: source,
            sourceWindowFrame: window,
            displays: [display],
            caretCandidate: nil
        )
        XCTAssertEqual(
            service.resolveMouseAnchor(
                at: SelectionPoint(x: 110, y: 940),
                sourceContext: context
            ),
            .rejected(.unsupportedText)
        )
        XCTAssertEqual(service.registeredContextCount, 0)
    }

    func testCopyAuthorizationRejectsContextDiscardedDuringValidation() async throws {
        let client = FakeAccessibilityClient()
        let text = client.addElement("text", pid: 10)
        let axWindow = client.addElement(
            "window",
            pid: 10,
            frame: CGRect(x: 0, y: 0, width: 500, height: 500),
            role: kAXWindowRole as String
        )
        client.setWindow(axWindow, for: text)
        client.configureMonospace(text, lines: ["abcdef"])
        client.focused = text
        client.selectedRange = CFRange(location: 1, length: 0)
        let service = MacOSAccessibilitySelectionService(
            client: client,
            windowValidator: { _, _ in true },
            secureInputEnabled: { false }
        )
        let activation = GridActivation(generation: 16)
        let session = SelectionSessionIdentity(rawValue: 26)
        let source = SelectionSourceIdentity(processIdentifier: 10, windowIdentifier: 4)
        let window = ScreenRectangle(x: 0, y: 0, width: 500, height: 500)
        let caret: GridCaretCandidate
        switch service.captureCaretCandidate(
            activation: activation,
            sessionIdentity: session,
            source: source,
            sourceWindowFrame: window,
            displays: [display]
        ) {
        case let .captured(candidate):
            caret = candidate
        default:
            return XCTFail("Expected captured caret")
        }
        var binder = GridSelectionContextBinder(
            activationContext: ActivationSourceContext(
                activation: activation,
                sessionIdentity: session,
                source: source,
                sourceWindowFrame: window,
                displays: [display],
                caretCandidate: caret
            )
        )
        guard case let .bound(context) = binder.bindKeyboardCaret() else {
            return XCTFail("Expected bound caret")
        }
        let enteredValidation = DispatchSemaphore(value: 0)
        let releaseValidation = DispatchSemaphore(value: 0)
        client.focusedElementBarrier = (enteredValidation, releaseValidation)

        let authorization = Task.detached {
            try await service.validateCopyAuthorization(for: context)
        }
        XCTAssertEqual(enteredValidation.wait(timeout: .now() + 2), .success)
        service.discardBoundContextsSynchronously(for: session)
        releaseValidation.signal()

        do {
            try await authorization.value
            XCTFail("Expected discarded context rejection")
        } catch let error as SelectionSourceFailureError {
            XCTAssertEqual(error.failure, .sourceContextInvalid)
        }
    }

    @MainActor
    func testAmbiguousSamePIDWindowFrameRejectsBeforeTextRead() {
        let client = FakeAccessibilityClient()
        let text = client.addElement("text", pid: 10)
        let firstWindow = client.addElement(
            "window-a",
            pid: 10,
            frame: CGRect(x: 0, y: 0, width: 500, height: 500),
            role: kAXWindowRole as String
        )
        _ = client.addElement(
            "window-b",
            pid: 10,
            frame: CGRect(x: 0, y: 0, width: 500, height: 500),
            role: kAXWindowRole as String
        )
        client.setWindow(firstWindow, for: text)
        client.configureMonospace(text, lines: ["ambiguous"])
        client.focused = text
        client.selectedRange = CFRange(location: 1, length: 0)
        let service = MacOSAccessibilitySelectionService(
            client: client,
            windowValidator: { _, _ in true },
            secureInputEnabled: { false }
        )

        switch service.captureCaretCandidate(
            activation: GridActivation(generation: 11),
            sessionIdentity: SelectionSessionIdentity(rawValue: 21),
            source: SelectionSourceIdentity(processIdentifier: 10, windowIdentifier: 4),
            sourceWindowFrame: ScreenRectangle(x: 0, y: 0, width: 500, height: 500),
            displays: [display]
        ) {
        case .rejected(.sourceContextInvalid):
            break
        default:
            XCTFail("Expected ambiguous window rejection")
        }
        XCTAssertEqual(client.textReadCount, 0)
        XCTAssertEqual(service.registeredContextCount, 0)
    }

    @MainActor
    func testUnreadableSiblingWindowFailsClosedBeforeTextRead() {
        let client = FakeAccessibilityClient()
        let text = client.addElement("text", pid: 10)
        let sourceWindow = client.addElement(
            "window-a",
            pid: 10,
            frame: CGRect(x: 0, y: 0, width: 500, height: 500),
            role: kAXWindowRole as String
        )
        _ = client.addElement(
            "window-b",
            pid: 10,
            frame: nil,
            role: kAXWindowRole as String
        )
        client.setWindow(sourceWindow, for: text)
        client.configureMonospace(text, lines: ["must not read"])
        client.focused = text
        client.selectedRange = CFRange(location: 1, length: 0)
        let service = MacOSAccessibilitySelectionService(
            client: client,
            windowValidator: { _, _ in true },
            secureInputEnabled: { false }
        )

        switch service.captureCaretCandidate(
            activation: GridActivation(generation: 14),
            sessionIdentity: SelectionSessionIdentity(rawValue: 24),
            source: SelectionSourceIdentity(processIdentifier: 10, windowIdentifier: 4),
            sourceWindowFrame: ScreenRectangle(x: 0, y: 0, width: 500, height: 500),
            displays: [display]
        ) {
        case .rejected(.sourceContextInvalid):
            break
        default:
            XCTFail("Expected unreadable window rejection")
        }
        XCTAssertEqual(client.textReadCount, 0)
        XCTAssertEqual(service.registeredContextCount, 0)
    }

    @MainActor
    func testSecureInputRejectsBeforeAccessibilityTextRead() {
        let client = FakeAccessibilityClient()
        let service = MacOSAccessibilitySelectionService(
            client: client,
            windowValidator: { _, _ in true },
            secureInputEnabled: { true }
        )

        switch service.captureCaretCandidate(
            activation: GridActivation(generation: 12),
            sessionIdentity: SelectionSessionIdentity(rawValue: 22),
            source: SelectionSourceIdentity(processIdentifier: 10, windowIdentifier: 4),
            sourceWindowFrame: ScreenRectangle(x: 0, y: 0, width: 500, height: 500),
            displays: [display]
        ) {
        case .rejected(.secureInputUnsupported):
            break
        default:
            XCTFail("Expected secure input rejection")
        }
        XCTAssertEqual(client.textReadCount, 0)
        XCTAssertEqual(client.boundsReadCount, 0)
        XCTAssertEqual(service.registeredContextCount, 0)
    }

    func testSecureInputEnabledDuringCaretSnapshotPreventsRegistration() async {
        let client = FakeAccessibilityClient()
        let text = client.addElement("text", pid: 10)
        let axWindow = client.addElement(
            "window",
            pid: 10,
            frame: CGRect(x: 0, y: 0, width: 500, height: 500),
            role: kAXWindowRole as String
        )
        client.setWindow(axWindow, for: text)
        client.configureMonospace(text, lines: ["abcdef"])
        client.focused = text
        client.selectedRange = CFRange(location: 1, length: 0)
        let enteredSnapshot = DispatchSemaphore(value: 0)
        let releaseSnapshot = DispatchSemaphore(value: 0)
        client.parameterizedNamesBarrier = (enteredSnapshot, releaseSnapshot)
        let secureInput = SecureInputFlag(false)
        let service = MacOSAccessibilitySelectionService(
            client: client,
            windowValidator: { _, _ in true },
            secureInputEnabled: { secureInput.value }
        )
        let displayGeometry = display

        let task = Task.detached {
            service.captureCaretCandidate(
                activation: GridActivation(generation: 13),
                sessionIdentity: SelectionSessionIdentity(rawValue: 23),
                source: SelectionSourceIdentity(processIdentifier: 10, windowIdentifier: 4),
                sourceWindowFrame: ScreenRectangle(x: 0, y: 0, width: 500, height: 500),
                displays: [displayGeometry]
            )
        }
        XCTAssertEqual(enteredSnapshot.wait(timeout: .now() + 2), .success)
        secureInput.value = true
        releaseSnapshot.signal()

        switch await task.value {
        case .rejected(.secureInputUnsupported):
            break
        default:
            XCTFail("Expected secure input rejection after snapshot")
        }
        XCTAssertEqual(service.registeredContextCount, 0)
    }

    private func engine(_ client: FakeAccessibilityClient) -> MacOSAccessibilityExtractionEngine {
        MacOSAccessibilityExtractionEngine(client: client)
    }

    private var display: DisplayGeometry {
        DisplayGeometry(
            displayID: 1,
            appKitFrame: ScreenRectangle(x: 0, y: 0, width: 1_000, height: 1_000),
            coreGraphicsBounds: ScreenRectangle(x: 0, y: 0, width: 1_000, height: 1_000),
            backingScale: 2
        )
    }

    private var selection: SelectionRectangle {
        SelectionRectangle(displayID: 1, x: 100, y: 930, width: 40, height: 20)
    }
}

private final class FakeAccessibilityClient: MacOSAccessibilityClient, @unchecked Sendable {
    struct ElementData {
        var pid: pid_t
        var frame: CGRect?
        var role: String?
        var subrole: String?
        var parentID: String?
        var childIDs: [String] = []
        var windowID: String?
        var parameterizedNames: [String] = []
        var visibleRange: CFRange?
        var numberOfCharacters: Int?
        var lines: [LineData] = []
        var characterWidths: [UInt16: Double] = [:]
    }

    struct LineData {
        let range: CFRange
        let rawText: String
        let bounds: CGRect
    }

    var isTrusted = true
    var hitTested: AccessibilityElementHandle?
    var focused: AccessibilityElementHandle?
    var selectedRange: CFRange?
    var elements: [String: ElementData] = [:]
    var forcedLineNumbers: (first: Int, last: Int)?
    var forcedString: String?
    var parameterizedNamesBarrier: (entered: DispatchSemaphore, release: DispatchSemaphore)?
    var focusedElementBarrier: (entered: DispatchSemaphore, release: DispatchSemaphore)?
    var pidUnavailableIDs: Set<String> = []
    var supportsSingleCharacterBounds = true
    var forcedChildCount: Int?
    private(set) var textReadCount = 0
    private(set) var boundsReadCount = 0
    private(set) var textReadsByElement: [String: Int] = [:]
    private(set) var hitTestCallCount = 0

    func addElement(
        _ id: String,
        pid: pid_t,
        frame: CGRect? = CGRect(x: 80, y: 40, width: 300, height: 200),
        role: String? = "AXTextArea",
        subrole: String? = nil
    ) -> AccessibilityElementHandle {
        elements[id] = ElementData(pid: pid, frame: frame, role: role, subrole: subrole)
        return AccessibilityElementHandle(testIdentifier: id)
    }

    func setParent(_ parent: AccessibilityElementHandle, for child: AccessibilityElementHandle) {
        elements[id(child)]?.parentID = id(parent)
        elements[id(parent)]?.childIDs.append(id(child))
    }

    func setWindow(_ window: AccessibilityElementHandle, for element: AccessibilityElementHandle) {
        elements[id(element)]?.windowID = id(window)
    }

    func configureMonospace(
        _ element: AccessibilityElementHandle,
        lines: [String],
        originX: Double = 100,
        originY: Double = 50,
        characterWidth: Double = 10,
        lineHeight: Double = 20,
        characterWidths: [Character: Double] = [:]
    ) {
        let identifier = id(element)
        var data = elements[identifier]!
        data.parameterizedNames = [
            kAXStringForRangeParameterizedAttribute,
            kAXBoundsForRangeParameterizedAttribute,
            kAXLineForIndexParameterizedAttribute,
            kAXRangeForLineParameterizedAttribute,
        ]
        var location = 0
        data.lines = lines.enumerated().map { index, text in
            let hasTerminator = index < lines.count - 1
            let rawText = text + (hasTerminator ? "\n" : "")
            let range = CFRange(location: location, length: rawText.utf16.count)
            location += rawText.utf16.count
            return LineData(
                range: range,
                rawText: rawText,
                bounds: CGRect(
                    x: originX,
                    y: originY + (Double(index) * lineHeight),
                    width: Double(text.utf16.count) * characterWidth,
                    height: lineHeight
                )
            )
        }
        data.visibleRange = CFRange(location: 0, length: location)
        data.numberOfCharacters = location
        data.characterWidths = Dictionary(
            uniqueKeysWithValues: characterWidths.compactMap { character, width in
                guard let codeUnit = character.utf16.first else {
                    return nil
                }
                return (codeUnit, width)
            }
        )
        if data.characterWidths.isEmpty {
            let allCodeUnits = lines.joined().utf16
            data.characterWidths = Dictionary(
                uniqueKeysWithValues: Set(allCodeUnits).map { ($0, characterWidth) }
            )
        }
        elements[identifier] = data
    }

    func hitTestedElement(
        at point: CGPoint,
        inProcess processIdentifier: pid_t?
    ) -> AccessibilityElementHandle? {
        hitTestCallCount += 1
        return hitTested
    }
    func focusedElement(inProcess processIdentifier: pid_t?) -> AccessibilityElementHandle? {
        if let barrier = focusedElementBarrier {
            barrier.entered.signal()
            _ = barrier.release.wait(timeout: .now() + 2)
        }
        focused
    }

    func parent(of element: AccessibilityElementHandle) -> AccessibilityElementHandle? {
        guard let parentID = elements[id(element)]?.parentID else {
            return nil
        }
        return AccessibilityElementHandle(testIdentifier: parentID)
    }

    func childCount(of element: AccessibilityElementHandle) -> Int? {
        forcedChildCount ?? elements[id(element)]?.childIDs.count
    }

    func children(
        of element: AccessibilityElementHandle,
        limit: Int
    ) -> [AccessibilityElementHandle]? {
        guard let identifiers = elements[id(element)]?.childIDs,
              identifiers.count <= limit
        else {
            return nil
        }
        return identifiers.map(AccessibilityElementHandle.init(testIdentifier:))
    }

    func window(of element: AccessibilityElementHandle) -> AccessibilityElementHandle? {
        guard let windowID = elements[id(element)]?.windowID else {
            return nil
        }
        return AccessibilityElementHandle(testIdentifier: windowID)
    }

    func windowCount(inProcess processIdentifier: pid_t) -> Int? {
        windowsForProcess(processIdentifier).count
    }

    func windows(
        inProcess processIdentifier: pid_t,
        limit: Int
    ) -> [AccessibilityElementHandle]? {
        let windows = windowsForProcess(processIdentifier)
        return windows.count <= limit ? windows : nil
    }

    private func windowsForProcess(
        _ processIdentifier: pid_t
    ) -> [AccessibilityElementHandle] {
        elements.compactMap { identifier, data in
            guard data.pid == processIdentifier,
                  data.role == (kAXWindowRole as String)
            else {
                return nil
            }
            return AccessibilityElementHandle(testIdentifier: identifier)
        }
    }

    func isSameElement(
        _ lhs: AccessibilityElementHandle,
        _ rhs: AccessibilityElementHandle
    ) -> Bool {
        id(lhs) == id(rhs)
    }

    func pid(of element: AccessibilityElementHandle) -> pid_t? {
        let identifier = id(element)
        return pidUnavailableIDs.contains(identifier) ? nil : elements[identifier]?.pid
    }
    func frame(of element: AccessibilityElementHandle) -> CGRect? { elements[id(element)]?.frame }
    func role(of element: AccessibilityElementHandle) -> String? { elements[id(element)]?.role }
    func subrole(of element: AccessibilityElementHandle) -> String? { elements[id(element)]?.subrole }
    func setMessagingTimeout(_ seconds: Float, for element: AccessibilityElementHandle) {}

    func parameterizedAttributeNames(of element: AccessibilityElementHandle) -> [String] {
        if let barrier = parameterizedNamesBarrier {
            barrier.entered.signal()
            _ = barrier.release.wait(timeout: .now() + 2)
        }
        return elements[id(element)]?.parameterizedNames ?? []
    }

    func visibleCharacterRange(of element: AccessibilityElementHandle) -> CFRange? {
        elements[id(element)]?.visibleRange
    }

    func selectedTextRange(of element: AccessibilityElementHandle) -> CFRange? {
        selectedRange
    }

    func numberOfCharacters(in element: AccessibilityElementHandle) -> Int? {
        elements[id(element)]?.numberOfCharacters
    }

    func line(for index: Int, in element: AccessibilityElementHandle) -> Int? {
        if let forcedLineNumbers {
            return index == elements[id(element)]?.visibleRange?.location
                ? forcedLineNumbers.first
                : forcedLineNumbers.last
        }
        return elements[id(element)]?.lines.firstIndex(where: {
            index >= $0.range.location && index < $0.range.location + $0.range.length
        })
    }

    func range(forLine line: Int, in element: AccessibilityElementHandle) -> CFRange? {
        guard let lines = elements[id(element)]?.lines, lines.indices.contains(line) else {
            return nil
        }
        return lines[line].range
    }

    func string(for range: CFRange, in element: AccessibilityElementHandle) -> String? {
        let identifier = id(element)
        textReadCount += 1
        textReadsByElement[identifier, default: 0] += 1
        if let forcedString {
            return forcedString
        }
        guard let line = elements[identifier]?.lines.first(where: {
            range.location >= $0.range.location
                && range.location + range.length <= $0.range.location + $0.range.length
        }) else {
            return nil
        }
        let start = range.location - line.range.location
        let units = Array(line.rawText.utf16)
        return String(decoding: units[start..<(start + range.length)], as: UTF16.self)
    }

    func bounds(for range: CFRange, in element: AccessibilityElementHandle) -> CGRect? {
        boundsReadCount += 1
        if range.length == 1, !supportsSingleCharacterBounds {
            return nil
        }
        guard let data = elements[id(element)],
              let line = data.lines.first(where: {
                  range.location >= $0.range.location
                      && range.location + range.length <= $0.range.location + $0.range.length
              })
        else {
            return nil
        }
        let offset = range.location - line.range.location
        let codeUnits = Array(line.rawText.utf16)
        guard offset >= 0, offset + range.length <= codeUnits.count else {
            return nil
        }
        let prefixWidth = codeUnits[..<offset].reduce(0.0) {
            $0 + (data.characterWidths[$1] ?? 10)
        }
        let width = codeUnits[offset..<(offset + range.length)].reduce(0.0) {
            $0 + (data.characterWidths[$1] ?? 10)
        }
        return CGRect(
            x: line.bounds.minX + prefixWidth,
            y: line.bounds.minY,
            width: width,
            height: line.bounds.height
        )
    }

    private func id(_ element: AccessibilityElementHandle) -> String {
        element.testIdentifier!
    }
}

private final class SecureInputFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Bool

    init(_ value: Bool) {
        storedValue = value
    }

    var value: Bool {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}
