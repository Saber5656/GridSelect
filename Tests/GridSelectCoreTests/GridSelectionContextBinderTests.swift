import XCTest
@testable import GridSelectCore

final class GridSelectionContextBinderTests: XCTestCase {
    func testKeyboardCaretBindsExactlyOnce() {
        let source = SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 9)
        let candidate = GridCaretCandidate(
            element: SelectionElementIdentity(rawValue: 17),
            anchor: GridBoundary(row: 3, column: 4),
            sourceRange: 12..<12,
            displayID: 1
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

    private func display(id: UInt32) -> DisplayGeometry {
        DisplayGeometry(
            displayID: id,
            appKitFrame: ScreenRectangle(x: 0, y: 0, width: 100, height: 100),
            coreGraphicsBounds: ScreenRectangle(x: 0, y: 0, width: 100, height: 100),
            backingScale: 2
        )
    }
}
