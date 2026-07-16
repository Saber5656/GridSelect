import GridSelectCore
import XCTest

final class GridOverlayInteractionTests: XCTestCase {
    func testKeyboardCaretStartsZeroWidthAndHandoffFreezesBeforeLaterArrow() throws {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: true))
        let initial = try XCTUnwrap(interaction.currentRectangle)
        XCTAssertEqual(initial.width, 0)
        XCTAssertEqual(initial.height, 20)

        let effects = interaction.applyHandoffCommands([
            .move(.right),
            .freeze,
            .move(.right),
        ])

        XCTAssertEqual(effects.count, 2)
        let frozen = try XCTUnwrap(interaction.currentRectangle)
        XCTAssertEqual(frozen.width, 10)
        XCTAssertEqual(frozen.height, 20)
    }

    func testZeroWidthCopyKeepsFrozenSelection() {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: true))
        XCTAssertNotNil(interaction.freeze())

        XCTAssertEqual(interaction.requestCopy(), .selectAtLeastOneColumn)
        XCTAssertNotNil(interaction.currentRectangle)
    }

    func testUnsupportedCaretAllowsSourceScopedMouseBindingAndCopy() throws {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: false))
        XCTAssertNil(interaction.currentRectangle)
        let candidate = mouseCandidate()

        guard case .accepted =
            interaction.beginMouseSelection(
                candidate: candidate,
                at: SelectionPoint(x: 125, y: 470)
            )
        else {
            return XCTFail("Expected mouse binding")
        }
        XCTAssertNotNil(
            interaction.moveMouseFocus(to: SelectionPoint(x: 135, y: 430))
        )
        XCTAssertNotNil(interaction.freeze())

        guard case let .copyRequested(rectangle, bound, authorization) =
            interaction.requestCopy()
        else {
            return XCTFail("Expected bound copy request")
        }
        XCTAssertEqual(rectangle.width, 10)
        XCTAssertEqual(rectangle.height, 60)
        XCTAssertEqual(bound.source, candidate.source)
        XCTAssertEqual(bound.element, candidate.element)
        XCTAssertEqual(authorization.selection.columnRange.count, 1)
    }

    func testMouseBindingRejectsAnotherSource() {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: false))
        let invalid = GridMouseAnchorCandidate(
            source: SelectionSourceIdentity(processIdentifier: 99, windowIdentifier: 7),
            element: SelectionElementIdentity(rawValue: 3),
            sourceRange: 0..<0,
            viewport: viewport()
        )

        XCTAssertEqual(
            interaction.beginMouseSelection(
                candidate: invalid,
                at: SelectionPoint(x: 110, y: 490)
            ),
            .rejected
        )
        XCTAssertNil(interaction.currentRectangle)
    }

    func testFrozenZeroWidthMayReanchorWithinSameBoundElement() throws {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: true))
        XCTAssertNotNil(interaction.freeze())
        guard case .accepted =
            interaction.beginMouseSelection(
                candidate: mouseCandidate(),
                at: SelectionPoint(x: 145, y: 450)
            )
        else {
            return XCTFail("Expected zero-width re-anchor")
        }

        let rectangle = try XCTUnwrap(interaction.currentRectangle)
        XCTAssertEqual(rectangle.x, 150)
        XCTAssertEqual(rectangle.y, 440)
        XCTAssertEqual(rectangle.width, 0)
    }

    func testAdjustingZeroWidthMayReanchorWithinSameBoundElement() throws {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: true))

        guard case .accepted = interaction.beginMouseSelection(
            candidate: mouseCandidate(),
            at: SelectionPoint(x: 145, y: 450)
        ) else {
            return XCTFail("Expected live zero-width caret to re-anchor")
        }

        XCTAssertEqual(interaction.binder.boundContext?.bindingOrigin, .mouseHit)
        XCTAssertEqual(try XCTUnwrap(interaction.currentRectangle).width, 0)
    }

    func testFrozenZeroWidthMayRebindToMouseHitTextElement() throws {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: true))
        XCTAssertNotNil(interaction.freeze())
        let mouseElement = SelectionElementIdentity(rawValue: 99)
        let candidate = GridMouseAnchorCandidate(
            source: interaction.sourceContext.source,
            element: mouseElement,
            sourceRange: 8..<8,
            viewport: viewport()
        )

        guard case .accepted = interaction.beginMouseSelection(
            candidate: candidate,
            at: SelectionPoint(x: 145, y: 450)
        ) else {
            return XCTFail("Expected zero-width selection to rebind to the mouse target")
        }

        XCTAssertEqual(interaction.binder.boundContext?.element, mouseElement)
        XCTAssertEqual(interaction.binder.boundContext?.sourceRange, 8..<8)
        XCTAssertEqual(interaction.binder.boundContext?.bindingOrigin, .mouseHit)
        XCTAssertEqual(try XCTUnwrap(interaction.currentRectangle).width, 0)
    }

    func testRejectedZeroWidthMouseRebindPreservesCaretBinding() {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: true))
        XCTAssertNotNil(interaction.freeze())
        let original = interaction.binder.boundContext
        let foreign = GridMouseAnchorCandidate(
            source: SelectionSourceIdentity(processIdentifier: 99, windowIdentifier: 7),
            element: SelectionElementIdentity(rawValue: 99),
            sourceRange: 8..<8,
            viewport: viewport()
        )

        XCTAssertEqual(
            interaction.beginMouseSelection(
                candidate: foreign,
                at: SelectionPoint(x: 145, y: 450)
            ),
            .rejected
        )
        XCTAssertEqual(interaction.binder.boundContext, original)
    }

    func testKeyboardNonzeroCopyCarriesExactBoundContext() {
        let sourceContext = context(withCaret: true)
        var interaction = GridOverlayInteraction(sourceContext: sourceContext)
        _ = interaction.moveKeyboardFocus(.right)
        _ = interaction.freeze()

        guard case let .copyRequested(rectangle, bound, authorization) =
            interaction.requestCopy()
        else {
            return XCTFail("Expected keyboard copy")
        }
        XCTAssertEqual(rectangle.width, 10)
        XCTAssertEqual(bound.activation, sourceContext.activation)
        XCTAssertEqual(bound.source, sourceContext.source)
        XCTAssertEqual(bound.element, sourceContext.caretCandidate?.element)
        XCTAssertEqual(authorization.activation, sourceContext.activation)
    }

    func testCopyCompletionRequiresExactLifecycleAuthorization() {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: true))
        _ = interaction.moveKeyboardFocus(.right)
        _ = interaction.freeze()
        guard case let .copyRequested(_, _, authorization) = interaction.requestCopy() else {
            return XCTFail("Expected copy authorization")
        }
        let stale = GridCopyAuthorization(
            activation: authorization.activation,
            sequence: authorization.sequence + 1,
            selection: authorization.selection
        )

        XCTAssertFalse(interaction.finishCopy(stale, succeeded: true))
        XCTAssertEqual(interaction.lifecycle.state, .copying(authorization))
        XCTAssertTrue(interaction.finishCopy(authorization, succeeded: true))
        XCTAssertEqual(
            interaction.lifecycle.state,
            .completed(authorization.activation)
        )
    }

    func testCopyCancellationRequiresExactLifecycleAuthorization() {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: true))
        _ = interaction.moveKeyboardFocus(.right)
        _ = interaction.freeze()
        guard case let .copyRequested(_, _, authorization) = interaction.requestCopy() else {
            return XCTFail("Expected copy authorization")
        }
        let stale = GridCopyAuthorization(
            activation: authorization.activation,
            sequence: authorization.sequence + 1,
            selection: authorization.selection
        )

        XCTAssertFalse(interaction.cancelCopy(stale))
        XCTAssertEqual(interaction.lifecycle.state, .copying(authorization))
        XCTAssertTrue(interaction.cancelCopy(authorization))
        XCTAssertEqual(
            interaction.lifecycle.state,
            .cancelled(authorization.activation)
        )
    }

    func testCancelStopsHandoffAndCopyThenCancelProcessesInOrder() {
        var cancelled = GridOverlayInteraction(sourceContext: context(withCaret: true))
        XCTAssertEqual(
            cancelled.applyHandoffCommands([
                .cancelRequested,
                .move(.right),
            ]),
            [.cancelled]
        )
        XCTAssertNil(cancelled.currentRectangle)

        let copiedContext = context(withCaret: true)
        var copied = GridOverlayInteraction(sourceContext: copiedContext)
        let effects = copied.applyHandoffCommands([
            .move(.right),
            .freeze,
            .copyRequested,
            .cancelRequested,
        ])
        guard effects.count == 4 else {
            return XCTFail("Expected move, freeze, copy, and cancel effects")
        }
        guard case .copyRequested = effects[2] else {
            return XCTFail("Expected copy request before cancellation")
        }
        XCTAssertEqual(effects[3], .cancelled)
        XCTAssertEqual(
            copied.lifecycle.state,
            .cancelled(copiedContext.activation)
        )
    }

    func testKeyboardCrossingAndLastRowRepeatRemainBounded() throws {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: true))
        _ = interaction.moveKeyboardFocus(.left)
        XCTAssertEqual(try XCTUnwrap(interaction.currentRectangle).x, 110)
        XCTAssertEqual(try XCTUnwrap(interaction.currentRectangle).width, 10)
        _ = interaction.moveKeyboardFocus(.left)
        XCTAssertEqual(try XCTUnwrap(interaction.currentRectangle).x, 100)
        XCTAssertEqual(try XCTUnwrap(interaction.currentRectangle).width, 20)
        _ = interaction.moveKeyboardFocus(.left)
        XCTAssertEqual(try XCTUnwrap(interaction.currentRectangle).x, 100)
        XCTAssertEqual(try XCTUnwrap(interaction.currentRectangle).width, 20)

        for _ in 0..<10 {
            _ = interaction.moveKeyboardFocus(.down)
        }
        let atBottom = try XCTUnwrap(interaction.currentRectangle)
        XCTAssertEqual(atBottom.height, 80)
        XCTAssertNil(interaction.moveKeyboardFocus(.down))
        _ = interaction.moveKeyboardFocus(.up)
        XCTAssertEqual(try XCTUnwrap(interaction.currentRectangle).height, 60)
    }

    func testFrozenNonzeroSelectionDoesNotReanchor() {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: true))
        _ = interaction.moveKeyboardFocus(.right)
        _ = interaction.freeze()

        XCTAssertEqual(
            interaction.beginMouseSelection(
                candidate: mouseCandidate(),
                at: SelectionPoint(x: 145, y: 450)
            ),
            .ignored
        )
        XCTAssertEqual(interaction.currentRectangle?.x, 120)
        XCTAssertEqual(interaction.currentRectangle?.width, 10)
    }

    func testFrozenNonzeroSelectionRejectsDifferentElementWithoutRebinding() {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: true))
        _ = interaction.moveKeyboardFocus(.right)
        _ = interaction.freeze()
        let originalBinding = interaction.binder.boundContext
        let originalRectangle = interaction.currentRectangle
        let differentElement = GridMouseAnchorCandidate(
            source: interaction.sourceContext.source,
            element: SelectionElementIdentity(rawValue: 99),
            sourceRange: 8..<8,
            viewport: viewport()
        )

        XCTAssertEqual(
            interaction.beginMouseSelection(
                candidate: differentElement,
                at: SelectionPoint(x: 145, y: 450)
            ),
            .rejected
        )
        XCTAssertEqual(interaction.binder.boundContext, originalBinding)
        XCTAssertEqual(interaction.currentRectangle, originalRectangle)
    }

    func testMouseFocusClampsToBoundDisplayAndPreservesDisplayIdentity() throws {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: false))
        guard case .accepted = interaction.beginMouseSelection(
            candidate: mouseCandidate(),
            at: SelectionPoint(x: 125, y: 470)
        ) else {
            return XCTFail("Expected mouse binding")
        }

        _ = interaction.moveMouseFocus(to: SelectionPoint(x: 900, y: -100))
        let rectangle = try XCTUnwrap(interaction.currentRectangle)
        XCTAssertEqual(rectangle.displayID, 1)
        XCTAssertEqual(rectangle.y, 400)
        XCTAssertLessThanOrEqual(rectangle.x + rectangle.width, 500)
    }

    func testMouseViewportMismatchRejectsWithoutBinding() {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: false))
        let mismatchedViewport = GridSelectionViewport(
            displayID: 2,
            originX: 500,
            topY: 500,
            characterWidth: 10,
            lineHeight: 20,
            visualRowCount: 5
        )
        let candidate = GridMouseAnchorCandidate(
            source: interaction.sourceContext.source,
            element: SelectionElementIdentity(rawValue: 3),
            sourceRange: 0..<0,
            viewport: mismatchedViewport
        )

        XCTAssertEqual(
            interaction.beginMouseSelection(
                candidate: candidate,
                at: SelectionPoint(x: 510, y: 490)
            ),
            .rejected
        )
        XCTAssertNil(interaction.binder.boundContext)
    }

    func testMouseCrossingUsesOneBoundaryPerCharacterWidthAndFreezePersists() throws {
        var interaction = GridOverlayInteraction(sourceContext: context(withCaret: false))
        guard case .accepted = interaction.beginMouseSelection(
            candidate: mouseCandidate(),
            at: SelectionPoint(x: 130, y: 470)
        ) else {
            return XCTFail("Expected mouse binding")
        }
        _ = interaction.moveMouseFocus(to: SelectionPoint(x: 120, y: 470))
        XCTAssertEqual(try XCTUnwrap(interaction.currentRectangle).x, 120)
        XCTAssertEqual(try XCTUnwrap(interaction.currentRectangle).width, 10)
        _ = interaction.moveMouseFocus(to: SelectionPoint(x: 110, y: 470))
        XCTAssertEqual(try XCTUnwrap(interaction.currentRectangle).width, 20)
        _ = interaction.moveMouseFocus(to: SelectionPoint(x: 140, y: 470))
        XCTAssertEqual(try XCTUnwrap(interaction.currentRectangle).x, 130)
        XCTAssertEqual(try XCTUnwrap(interaction.currentRectangle).width, 10)

        let beforeFreeze = interaction.currentRectangle
        XCTAssertNotNil(interaction.freeze())
        XCTAssertEqual(interaction.currentRectangle, beforeFreeze)
        XCTAssertNil(interaction.moveMouseFocus(to: SelectionPoint(x: 150, y: 470)))
        XCTAssertEqual(interaction.currentRectangle, beforeFreeze)
    }

    func testSessionGuardRejectsStaleCallbacksAndUnacceptedDrags() {
        var guardState = GridOverlaySessionGuard()
        let first = guardState.begin()
        XCTAssertFalse(guardState.acceptsMouseEvent(displayID: 1, generation: first))
        XCTAssertTrue(guardState.beginMouseDrag(displayID: 1, generation: first))
        XCTAssertTrue(guardState.acceptsMouseEvent(displayID: 1, generation: first))

        let second = guardState.begin()
        XCTAssertFalse(guardState.isCurrent(first))
        XCTAssertFalse(guardState.beginMouseDrag(displayID: 1, generation: first))
        XCTAssertFalse(guardState.acceptsMouseEvent(displayID: 1, generation: first))
        XCTAssertTrue(guardState.isCurrent(second))
        XCTAssertNil(guardState.activeMouseDisplayID)
    }

    private func context(withCaret: Bool) -> ActivationSourceContext {
        let source = SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 7)
        return ActivationSourceContext(
            activation: GridActivation(generation: 1),
            source: source,
            sourceWindowFrame: ScreenRectangle(x: 0, y: 0, width: 500, height: 500),
            displays: [display()],
            caretCandidate: withCaret
                ? GridCaretCandidate(
                    element: SelectionElementIdentity(rawValue: 3),
                    anchor: GridBoundary(row: 1, column: 2),
                    sourceRange: 4..<4,
                    displayID: 1,
                    viewport: viewport()
                )
                : nil
        )
    }

    private func mouseCandidate() -> GridMouseAnchorCandidate {
        GridMouseAnchorCandidate(
            source: SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 7),
            element: SelectionElementIdentity(rawValue: 3),
            sourceRange: 4..<4,
            viewport: viewport()
        )
    }

    private func viewport() -> GridSelectionViewport {
        GridSelectionViewport(
            displayID: 1,
            originX: 100,
            topY: 500,
            characterWidth: 10,
            lineHeight: 20,
            visualRowCount: 5
        )
    }

    private func display() -> DisplayGeometry {
        DisplayGeometry(
            displayID: 1,
            appKitFrame: ScreenRectangle(x: 0, y: 0, width: 500, height: 500),
            coreGraphicsBounds: ScreenRectangle(x: 0, y: 0, width: 500, height: 500),
            backingScale: 2
        )
    }
}
