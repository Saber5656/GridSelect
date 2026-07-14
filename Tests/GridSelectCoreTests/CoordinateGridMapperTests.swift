@testable import GridSelectCore
import XCTest

final class CoordinateGridMapperTests: XCTestCase {
    private let mapper = CoordinateGridMapper()

    func testConvertsAppKitRectangleToCanonicalSpaceOnceWithNegativeDisplayOrigin() throws {
        let display = DisplayGeometry(
            displayID: 3,
            appKitFrame: ScreenRectangle(x: -1_440, y: 180, width: 1_440, height: 900),
            coreGraphicsBounds: ScreenRectangle(x: -1_440, y: 0, width: 1_440, height: 900),
            backingScale: 2
        )
        let selection = SelectionRectangle(
            displayID: 3,
            x: -1_320,
            y: 220,
            width: 680,
            height: 460
        )

        XCTAssertEqual(
            display.canonicalRectangle(for: selection),
            ScreenRectangle(x: -1_320, y: 400, width: 680, height: 460)
        )
    }

    func testExactRightAndBottomBoundariesDoNotIncludeNextCells() throws {
        let result = mapper.map(
            selection: selection(canonicalX: 120, y: 50, width: 50, height: 40),
            display: display,
            grid: grid,
            visualLines: lines
        )
        let mapped = try selection(from: result)

        XCTAssertEqual(mapped.rowRange, 0..<2)
        XCTAssertEqual(mapped.columnRange, 2..<7)
        XCTAssertEqual(mapped.plainText, "pha b\narlie")
    }

    func testPartialCellsAreIncludedAndLeftEdgeIsClamped() throws {
        let result = mapper.map(
            selection: selection(canonicalX: 96, y: 52, width: 19, height: 37),
            display: display,
            grid: grid,
            visualLines: lines
        )
        let mapped = try selection(from: result)

        XCTAssertEqual(mapped.rowRange, 0..<2)
        XCTAssertEqual(mapped.columnRange, 0..<2)
        XCTAssertEqual(mapped.plainText, "al\nch")
        XCTAssertTrue(mapped.diagnostics.contains(.clampedLeft))
    }

    func testSelectionsOutsideMeasuredRowsOrEntirelyLeftAreEmpty() {
        let above = mapper.map(
            selection: selection(canonicalX: 100, y: 0, width: 20, height: 20),
            display: display,
            grid: grid,
            visualLines: lines
        )
        let below = mapper.map(
            selection: selection(canonicalX: 100, y: 120, width: 20, height: 20),
            display: display,
            grid: grid,
            visualLines: lines
        )
        let left = mapper.map(
            selection: selection(canonicalX: 60, y: 50, width: 40, height: 20),
            display: display,
            grid: grid,
            visualLines: lines
        )

        XCTAssertEqual(above, .empty)
        XCTAssertEqual(below, .empty)
        XCTAssertEqual(left, .empty)
    }

    func testShortAndEmptyLinesPreserveRectangularPadding() throws {
        let result = mapper.map(
            selection: selection(canonicalX: 120, y: 50, width: 40, height: 60),
            display: display,
            grid: grid,
            visualLines: [VisualLine(text: "abc"), VisualLine(text: "abcdef"), VisualLine(text: "")]
        )
        let mapped = try selection(from: result)

        XCTAssertEqual(mapped.plainText, "c   \ncdef\n    ")
        XCTAssertEqual(mapped.rows.map(\.missingCellCount), [3, 0, 4])
        XCTAssertTrue(mapped.diagnostics.contains(.rightPadded))
    }

    func testKnownTabStopExpandsBeforeSlicing() throws {
        let result = mapper.map(
            selection: selection(canonicalX: 110, y: 50, width: 40, height: 20),
            display: display,
            grid: grid,
            visualLines: [VisualLine(text: "a\tb")],
            policy: GridMappingPolicy(tabStop: 4)
        )
        let mapped = try selection(from: result)

        XCTAssertEqual(mapped.plainText, "   b")
        XCTAssertTrue(mapped.diagnostics.contains(.tabExpanded))
    }

    func testUnknownTabStopReturnsActionableUnsupportedReason() {
        let result = mapper.map(
            selection: selection(canonicalX: 100, y: 50, width: 50, height: 20),
            display: display,
            grid: grid,
            visualLines: [VisualLine(text: "a\tb")]
        )

        XCTAssertEqual(result, .unsupported(.tabStopUnknown))
    }

    func testVariableWidthEmojiAndCombiningContentAreRejected() {
        for text in ["café", "ok🙂"] {
            XCTAssertEqual(
                mapper.map(
                    selection: selection(canonicalX: 100, y: 50, width: 50, height: 20),
                    display: display,
                    grid: grid,
                    visualLines: [VisualLine(text: text)]
                ),
                .unsupported(.variableWidthContent)
            )
        }

        XCTAssertEqual(
            mapper.map(
                selection: selection(canonicalX: 100, y: 50, width: 50, height: 20),
                display: display,
                grid: grid,
                visualLines: [VisualLine(text: "e\u{301}")]
            ),
            .unsupported(.combiningCharacterContent)
        )
    }

    func testUnsupportedContentAfterSelectedColumnsIsIgnored() throws {
        let result = mapper.map(
            selection: selection(canonicalX: 100, y: 50, width: 20, height: 20),
            display: display,
            grid: grid,
            visualLines: [VisualLine(text: "ab🙂")]
        )

        try XCTAssertEqual(try selection(from: result).plainText, "ab")
    }

    func testStartBoundariesSnapWithinFloatingPointEpsilon() throws {
        let result = mapper.map(
            selection: selection(
                canonicalX: 120 - 0.000000001,
                y: 70 - 0.000000001,
                width: 20.000000001,
                height: 20.000000001
            ),
            display: display,
            grid: grid,
            visualLines: lines
        )
        let mapped = try selection(from: result)

        XCTAssertEqual(mapped.rowRange, 1..<2)
        XCTAssertEqual(mapped.columnRange, 2..<4)
    }

    func testOversizedRequestedGridIsRejectedBeforePadding() {
        let result = mapper.map(
            selection: selection(canonicalX: 100, y: 50, width: 40, height: 20),
            display: display,
            grid: TextGridGeometry(
                originX: 100,
                originY: 50,
                characterWidth: 0.0001,
                lineHeight: 20
            ),
            visualLines: [VisualLine(text: "a")]
        )

        XCTAssertEqual(result, .unsupported(.selectionTooLarge))
    }

    func testNonFiniteGeometryIsRejectedWithoutIntegerConversion() {
        let result = mapper.map(
            selection: selection(canonicalX: 100, y: 50, width: .infinity, height: 20),
            display: display,
            grid: grid,
            visualLines: lines
        )

        XCTAssertEqual(result, .unsupported(.invalidGeometry))
    }

    func testExtremeFiniteCoordinatesAreRejectedWithoutIntegerConversion() {
        let result = mapper.map(
            selection: selection(
                canonicalX: 100,
                y: 50,
                width: .greatestFiniteMagnitude,
                height: 20
            ),
            display: display,
            grid: grid,
            visualLines: lines
        )

        XCTAssertEqual(result, .unsupported(.selectionTooLarge))
    }

    func testHugeTabStopOnlyExpandsThroughSelectedColumns() throws {
        let result = mapper.map(
            selection: selection(canonicalX: 100, y: 50, width: 10, height: 20),
            display: display,
            grid: grid,
            visualLines: [VisualLine(text: "\t")],
            policy: GridMappingPolicy(tabStop: .max)
        )

        let mapped = try selection(from: result)
        XCTAssertEqual(mapped.plainText, " ")
        XCTAssertTrue(mapped.diagnostics.contains(.tabExpanded))
    }

    func testFarRightSelectionDoesNotMaterializeTabPrefix() throws {
        let selectedColumn = 1_000_000_000
        let result = mapper.map(
            selection: selection(
                canonicalX: 100 + (Double(selectedColumn) * 10),
                y: 50,
                width: 10,
                height: 20
            ),
            display: display,
            grid: grid,
            visualLines: [VisualLine(text: "\t")],
            policy: GridMappingPolicy(tabStop: .max)
        )

        let mapped = try selection(from: result)
        XCTAssertEqual(mapped.columnRange, selectedColumn..<(selectedColumn + 1))
        XCTAssertEqual(mapped.plainText, " ")
        XCTAssertTrue(mapped.diagnostics.contains(.tabExpanded))
    }

    func testSoftWrappedRowsRemainIndependentVisualRows() throws {
        let result = mapper.map(
            selection: selection(canonicalX: 120, y: 70, width: 30, height: 20),
            display: display,
            grid: grid,
            visualLines: [
                VisualLine(text: "abcdefghij"),
                VisualLine(text: "klmnopqrst", isSoftWrapped: true),
            ]
        )
        let mapped = try selection(from: result)

        XCTAssertEqual(mapped.rowRange, 1..<2)
        XCTAssertEqual(mapped.plainText, "mno")
        XCTAssertTrue(mapped.diagnostics.contains(.softWrappedVisualRow))
    }

    func testDisplayMismatchIsUnsupportedRatherThanComparingRawCoordinates() {
        let result = mapper.map(
            selection: SelectionRectangle(displayID: 99, x: 0, y: 0, width: 10, height: 10),
            display: display,
            grid: grid,
            visualLines: lines
        )

        XCTAssertEqual(result, .unsupported(.displayMismatch))
    }

    func testRetinaGeometryStaysInPointsAndRecordsScaleDiagnostic() throws {
        let result = mapper.map(
            selection: selection(canonicalX: 100, y: 50, width: 10, height: 20),
            display: display,
            grid: grid,
            visualLines: lines
        )
        let mapped = try selection(from: result)

        XCTAssertEqual(mapped.columnRange, 0..<1)
        XCTAssertTrue(mapped.diagnostics.contains(.retinaPoints(backingScale: 2)))
    }

    private var display: DisplayGeometry {
        DisplayGeometry(
            displayID: 1,
            appKitFrame: ScreenRectangle(x: 0, y: 0, width: 1_000, height: 1_000),
            coreGraphicsBounds: ScreenRectangle(x: 0, y: 0, width: 1_000, height: 1_000),
            backingScale: 2
        )
    }

    private var grid: TextGridGeometry {
        TextGridGeometry(originX: 100, originY: 50, characterWidth: 10, lineHeight: 20)
    }

    private var lines: [VisualLine] {
        [VisualLine(text: "alpha bravo"), VisualLine(text: "charlie delta"), VisualLine(text: "echo foxtrot")]
    }

    private func selection(canonicalX: Double, y: Double, width: Double, height: Double) -> SelectionRectangle {
        SelectionRectangle(
            displayID: 1,
            x: canonicalX,
            y: 1_000 - (y + height),
            width: width,
            height: height
        )
    }

    private func selection(from result: GridMappingResult) throws -> GridSelection {
        guard case let .selection(selection) = result else {
            XCTFail("Expected mapped selection, got \(result)")
            throw TestError.unexpectedResult
        }
        return selection
    }

    private enum TestError: Error {
        case unexpectedResult
    }
}
