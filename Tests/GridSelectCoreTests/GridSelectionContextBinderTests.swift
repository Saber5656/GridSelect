import XCTest
@testable import GridSelectCore

final class GridSelectionContextBinderTests: XCTestCase {
    func testKeyboardCaretBindsExactlyOnce() {
        let source = SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 9)
        let viewport = GridSelectionViewport(
            displayID: 1,
            originX: 10,
            topY: 100,
            characterWidth: 8,
            lineHeight: 16,
            visualRowCount: 4
        )
        let candidate = GridCaretCandidate(
            element: SelectionElementIdentity(rawValue: 17),
            anchor: GridBoundary(row: 3, column: 4),
            sourceRange: 12..<12,
            displayID: 1,
            viewport: viewport
        )
        var binder = GridSelectionContextBinder(
            activationContext: ActivationSourceContext(
                activation: GridActivation(generation: 2),
                source: source,
                sourceWindowFrame: ScreenRectangle(x: 0, y: 0, width: 80, height: 80),
                displays: [display(id: 1)],
                caretCandidate: candidate
            )
        )

        guard case let .bound(bound) = binder.bindKeyboardCaret() else {
            return XCTFail("Expected keyboard binding")
        }
        XCTAssertEqual(bound.source, source)
        XCTAssertEqual(bound.element, candidate.element)
        XCTAssertEqual(bound.anchor, candidate.anchor)
        XCTAssertEqual(bound.viewport, viewport)
        XCTAssertEqual(binder.bindKeyboardCaret(), .rejected(.alreadyBound))
    }

    func testMouseBindingRejectsCrossSourceAndUnknownDisplay() {
        let source = SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 9)
        let other = SelectionSourceIdentity(processIdentifier: 43, windowIdentifier: 9)
        var binder = GridSelectionContextBinder(
            activationContext: ActivationSourceContext(
                activation: GridActivation(generation: 2),
                source: source,
                sourceWindowFrame: ScreenRectangle(x: 0, y: 0, width: 80, height: 80),
                displays: [display(id: 1)],
                caretCandidate: nil
            )
        )

        XCTAssertEqual(
            binder.bindMouseAnchor(
                source: other,
                element: SelectionElementIdentity(rawValue: 1),
                anchor: GridBoundary(row: 0, column: 0),
                sourceRange: 0..<0,
                displayID: 1
            ),
            .rejected(.sourceMismatch)
        )
        XCTAssertEqual(
            binder.bindMouseAnchor(
                source: source,
                element: SelectionElementIdentity(rawValue: 1),
                anchor: GridBoundary(row: 0, column: 0),
                sourceRange: 0..<0,
                displayID: 2
            ),
            .rejected(.displayUnavailable)
        )
        XCTAssertNil(binder.boundContext)
    }

    func testBindingRejectsMismatchedViewportAndOutOfRangeAnchor() {
        let source = SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 9)
        let mismatched = GridCaretCandidate(
            element: SelectionElementIdentity(rawValue: 17),
            anchor: GridBoundary(row: 0, column: 0),
            sourceRange: 0..<0,
            displayID: 1,
            viewport: viewport(displayID: 2, rows: 2)
        )
        var mismatchedBinder = GridSelectionContextBinder(
            activationContext: context(source: source, candidate: mismatched)
        )
        XCTAssertEqual(
            mismatchedBinder.bindKeyboardCaret(),
            .rejected(.invalidViewport)
        )
        XCTAssertNil(mismatchedBinder.boundContext)

        let outOfRange = GridCaretCandidate(
            element: SelectionElementIdentity(rawValue: 17),
            anchor: GridBoundary(row: 2, column: 0),
            sourceRange: 0..<0,
            displayID: 1,
            viewport: viewport(displayID: 1, rows: 2)
        )
        var rangeBinder = GridSelectionContextBinder(
            activationContext: context(source: source, candidate: outOfRange)
        )
        XCTAssertEqual(rangeBinder.bindKeyboardCaret(), .rejected(.invalidViewport))
        XCTAssertNil(rangeBinder.boundContext)
    }

    private func context(
        source: SelectionSourceIdentity,
        candidate: GridCaretCandidate
    ) -> ActivationSourceContext {
        ActivationSourceContext(
            activation: GridActivation(generation: 2),
            source: source,
            sourceWindowFrame: ScreenRectangle(x: 0, y: 0, width: 80, height: 80),
            displays: [display(id: 1), display(id: 2)],
            caretCandidate: candidate
        )
    }

    private func viewport(displayID: UInt32, rows: Int) -> GridSelectionViewport {
        GridSelectionViewport(
            displayID: displayID,
            originX: 0,
            topY: 100,
            characterWidth: 8,
            lineHeight: 16,
            visualRowCount: rows
        )
    }

    private func display(id: UInt32) -> DisplayGeometry {
        DisplayGeometry(
            displayID: id,
            appKitFrame: ScreenRectangle(x: 0, y: 0, width: 100, height: 100),
            coreGraphicsBounds: ScreenRectangle(x: 0, y: 0, width: 100, height: 100),
            backingScale: 2
        )
    }
}
