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

        guard case let .copyRequested(rectangle, bound) = interaction.requestCopy() else {
            return XCTFail("Expected bound copy request")
        }
        XCTAssertEqual(rectangle.width, 10)
        XCTAssertEqual(rectangle.height, 60)
        XCTAssertEqual(bound.source, candidate.source)
        XCTAssertEqual(bound.element, candidate.element)
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

    func testKeyboardNonzeroCopyCarriesExactBoundContext() {
        let sourceContext = context(withCaret: true)
        var interaction = GridOverlayInteraction(sourceContext: sourceContext)
        _ = interaction.moveKeyboardFocus(.right)
        _ = interaction.freeze()

        guard case let .copyRequested(rectangle, bound) = interaction.requestCopy() else {
            return XCTFail("Expected keyboard copy")
        }
        XCTAssertEqual(rectangle.width, 10)
        XCTAssertEqual(bound.activation, sourceContext.activation)
        XCTAssertEqual(bound.source, sourceContext.source)
        XCTAssertEqual(bound.element, sourceContext.caretCandidate?.element)
    }

    func testCancelAndCopyHandoffStopLaterCommands() {
        var cancelled = GridOverlayInteraction(sourceContext: context(withCaret: true))
        XCTAssertEqual(
            cancelled.applyHandoffCommands([
                .cancelRequested,
                .move(.right),
            ]),
            [.cancelled]
        )
        XCTAssertNil(cancelled.currentRectangle)

        var copied = GridOverlayInteraction(sourceContext: context(withCaret: true))
        let effects = copied.applyHandoffCommands([
            .move(.right),
            .freeze,
            .copyRequested,
            .cancelRequested,
        ])
        XCTAssertEqual(effects.count, 3)
        guard let last = effects.last, case .copyRequested = last else {
            return XCTFail("Expected copy to stop replay")
        }
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

    func testNonAlignedViewportCapsKeyboardAndMouseAtLastVisibleBoundary() throws {
        let viewport = GridSelectionViewport(
            displayID: 1,
            originX: 103,
            topY: 500,
            characterWidth: 10,
            lineHeight: 20,
            visualRowCount: 5
        )
        let source = SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 7)
        let context = ActivationSourceContext(
            activation: GridActivation(generation: 1),
            source: source,
            sourceWindowFrame: ScreenRectangle(x: 0, y: 0, width: 500, height: 500),
            displays: [display()],
            caretCandidate: GridCaretCandidate(
                element: SelectionElementIdentity(rawValue: 3),
                anchor: GridBoundary(row: 1, column: 38),
                sourceRange: 4..<4,
                displayID: 1,
                viewport: viewport
            )
        )
        var keyboard = GridOverlayInteraction(sourceContext: context)
        XCTAssertNotNil(keyboard.moveKeyboardFocus(.right))
        XCTAssertNil(keyboard.moveKeyboardFocus(.right))
        XCTAssertEqual(try XCTUnwrap(keyboard.currentRectangle).x, 483)
        XCTAssertEqual(try XCTUnwrap(keyboard.currentRectangle).width, 10)

        var mouse = GridOverlayInteraction(
            sourceContext: ActivationSourceContext(
                activation: context.activation,
                source: source,
                sourceWindowFrame: context.sourceWindowFrame,
                displays: context.displays,
                caretCandidate: nil
            )
        )
        let candidate = GridMouseAnchorCandidate(
            source: source,
            element: SelectionElementIdentity(rawValue: 3),
            sourceRange: 4..<4,
            viewport: viewport
        )
        guard case .accepted = mouse.beginMouseSelection(
            candidate: candidate,
            at: SelectionPoint(x: 500, y: 470)
        ) else {
            return XCTFail("Expected right-edge pointer to clamp and bind")
        }
        XCTAssertEqual(try XCTUnwrap(mouse.currentRectangle).x, 493)
        XCTAssertNotNil(mouse.moveMouseFocus(to: SelectionPoint(x: 900, y: 470)))
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(mouse.currentRectangle).x
                + try XCTUnwrap(mouse.currentRectangle).width,
            500
        )
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
