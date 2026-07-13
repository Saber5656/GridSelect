@testable import GridSelectCore
import XCTest

final class SelectionDragGeometryTests: XCTestCase {
    func testNormalizesReverseDragIntoGlobalScreenPoints() {
        let geometry = SelectionDragGeometry(
            displayID: 9,
            screenOrigin: SelectionPoint(x: -1440, y: 180),
            screenWidth: 1440,
            screenHeight: 900
        )

        let rectangle = geometry.rectangle(
            from: SelectionPoint(x: 800, y: 500),
            to: SelectionPoint(x: 120, y: 40)
        )

        XCTAssertEqual(
            rectangle,
            SelectionRectangle(
                displayID: 9,
                x: -1320,
                y: 220,
                width: 680,
                height: 460
            )
        )
    }

    func testClampsDragToItsSourceDisplay() {
        let geometry = SelectionDragGeometry(
            displayID: 3,
            screenOrigin: SelectionPoint(x: 0, y: 0),
            screenWidth: 1920,
            screenHeight: 1080
        )

        let rectangle = geometry.rectangle(
            from: SelectionPoint(x: -50, y: 100),
            to: SelectionPoint(x: 2_400, y: 1_200)
        )

        XCTAssertEqual(
            rectangle,
            SelectionRectangle(
                displayID: 3,
                x: 0,
                y: 100,
                width: 1920,
                height: 980
            )
        )
    }

    func testUsesPointsWithoutApplyingBackingScale() {
        let geometry = SelectionDragGeometry(
            displayID: 1,
            screenOrigin: SelectionPoint(x: 100, y: 200),
            screenWidth: 1_512,
            screenHeight: 982
        )

        let rectangle = geometry.rectangle(
            from: SelectionPoint(x: 10.5, y: 20.25),
            to: SelectionPoint(x: 110.5, y: 70.25)
        )

        XCTAssertEqual(rectangle.x, 110.5)
        XCTAssertEqual(rectangle.y, 220.25)
        XCTAssertEqual(rectangle.width, 100)
        XCTAssertEqual(rectangle.height, 50)
    }

    func testRejectsAccidentalClickBelowMinimumSize() {
        let geometry = SelectionDragGeometry(
            displayID: 5,
            screenOrigin: SelectionPoint(x: 0, y: 0),
            screenWidth: 100,
            screenHeight: 100,
            minimumSelectionSize: 4
        )

        let tooNarrow = geometry.rectangle(
            from: SelectionPoint(x: 10, y: 10),
            to: SelectionPoint(x: 13.99, y: 50)
        )
        let minimum = geometry.rectangle(
            from: SelectionPoint(x: 10, y: 10),
            to: SelectionPoint(x: 14, y: 14)
        )

        XCTAssertFalse(geometry.isConfirmable(tooNarrow))
        XCTAssertTrue(geometry.isConfirmable(minimum))
    }

    func testRejectsRectangleFromAnotherDisplay() {
        let geometry = SelectionDragGeometry(
            displayID: 5,
            screenOrigin: SelectionPoint(x: 0, y: 0),
            screenWidth: 100,
            screenHeight: 100
        )
        let rectangle = SelectionRectangle(
            displayID: 6,
            x: 10,
            y: 10,
            width: 20,
            height: 20
        )

        XCTAssertFalse(geometry.isConfirmable(rectangle))
    }
}
