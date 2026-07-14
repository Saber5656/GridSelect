import GridSelectCore
import XCTest

final class GridSelectionViewportTests: XCTestCase {
    private let viewport = GridSelectionViewport(
        displayID: 7,
        originX: 100,
        topY: 500,
        characterWidth: 10,
        lineHeight: 20,
        visualRowCount: 4
    )

    func testInitialAnchorMidpointChoosesTrailingBoundary() {
        XCTAssertEqual(
            viewport.boundary(
                at: SelectionPoint(x: 125, y: 490),
                role: .initialAnchor
            ),
            GridBoundary(row: 0, column: 3)
        )
    }

    func testFocusMidpointChoosesBoundaryFartherFromAnchor() {
        XCTAssertEqual(
            viewport.boundary(
                at: SelectionPoint(x: 125, y: 470),
                role: .focus(anchorColumn: 1)
            ),
            GridBoundary(row: 1, column: 3)
        )
        XCTAssertEqual(
            viewport.boundary(
                at: SelectionPoint(x: 125, y: 470),
                role: .focus(anchorColumn: 4)
            ),
            GridBoundary(row: 1, column: 2)
        )
    }

    func testPointSnappingClampsNegativeColumnsAndVerticalRows() {
        XCTAssertEqual(
            viewport.boundary(
                at: SelectionPoint(x: -50, y: 800),
                role: .initialAnchor
            ),
            GridBoundary(row: 0, column: 0)
        )
        XCTAssertEqual(
            viewport.boundary(
                at: SelectionPoint(x: 110, y: 100),
                role: .initialAnchor
            ),
            GridBoundary(row: 3, column: 1)
        )
    }

    func testKeyboardAndMouseBoundariesProduceSameAppKitRectangle() throws {
        let selection = GridIndexSelection(
            anchor: GridBoundary(row: 1, column: 2),
            focus: GridBoundary(row: 3, column: 3)
        )
        let rectangle = try XCTUnwrap(viewport.rectangle(for: selection))

        XCTAssertEqual(
            rectangle,
            SelectionRectangle(
                displayID: 7,
                x: 120,
                y: 420,
                width: 10,
                height: 60
            )
        )
    }

    func testZeroWidthStillProducesVisibleRowExtent() throws {
        let rectangle = try XCTUnwrap(
            viewport.rectangle(
                for: GridIndexSelection(anchor: GridBoundary(row: 2, column: 4))
            )
        )

        XCTAssertEqual(rectangle.width, 0)
        XCTAssertEqual(rectangle.height, 20)
        XCTAssertEqual(rectangle.x, 140)
        XCTAssertEqual(rectangle.y, 440)
    }

    func testFractionalPointGeometryDoesNotApplyBackingScale() throws {
        let retinaViewport = GridSelectionViewport(
            displayID: 8,
            originX: 0.25,
            topY: 100.75,
            characterWidth: 7.5,
            lineHeight: 15.5,
            visualRowCount: 2
        )
        let rectangle = try XCTUnwrap(
            retinaViewport.rectangle(
                for: GridIndexSelection(
                    anchor: GridBoundary(row: 0, column: 1),
                    focus: GridBoundary(row: 1, column: 2)
                )
            )
        )

        XCTAssertEqual(rectangle.x, 7.75)
        XCTAssertEqual(rectangle.y, 69.75)
        XCTAssertEqual(rectangle.width, 7.5)
        XCTAssertEqual(rectangle.height, 31)
    }

    func testInvalidGeometryFailsClosed() {
        let invalid = GridSelectionViewport(
            displayID: 1,
            originX: 0,
            topY: 0,
            characterWidth: 0,
            lineHeight: 10,
            visualRowCount: 1
        )

        XCTAssertNil(
            invalid.boundary(
                at: SelectionPoint(x: 0, y: 0),
                role: .initialAnchor
            )
        )
        XCTAssertNil(
            invalid.rectangle(
                for: GridIndexSelection(anchor: GridBoundary(row: 0, column: 0))
            )
        )
    }
}
