import GridSelectCore
import XCTest

final class TextGridTests: XCTestCase {
    func testSlicePreservesRowOrderAndColumnBounds() {
        let grid = TextGrid(rows: [
            "alpha",
            "bravo",
            "charlie"
        ])

        XCTAssertEqual(
            grid.slice(rows: 0..<2, columns: 1..<4),
            "lph\nrav"
        )
    }

    func testSlicePreservesSpaces() {
        let grid = TextGrid(rows: [
            "aa  bb",
            "cc  dd"
        ])

        XCTAssertEqual(
            grid.slice(rows: 0..<2, columns: 2..<6),
            "  bb\n  dd"
        )
    }

    func testSliceClampsRowsAndColumnsToAvailableText() {
        let grid = TextGrid(rows: [
            "abc",
            "def"
        ])

        XCTAssertEqual(
            grid.slice(rows: -4..<10, columns: 1..<10),
            "bc\nef"
        )
    }

    func testSliceReturnsEmptyTextForEmptyRanges() {
        let grid = TextGrid(rows: ["abc"])

        XCTAssertEqual(grid.slice(rows: 0..<0, columns: 0..<2), "")
        XCTAssertEqual(grid.slice(rows: 0..<1, columns: 2..<2), "")
        XCTAssertEqual(grid.slice(rows: 3..<5, columns: 0..<2), "")
    }
}
