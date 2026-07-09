import GridSelectCore
import XCTest

final class ClipboardTextFormatterTests: XCTestCase {
    private let formatter = ClipboardTextFormatter()

    func testFormatsBasicRectangularSlice() {
        let result = formatter.format(
            rows: [
                "0123456789",
                "abcdefghij",
                "KLMNOPQRST"
            ],
            rows: 0..<3,
            columns: 2..<7
        )

        XCTAssertEqual(result.plainText, "23456\ncdefg\nMNOPQ")
    }

    func testPreservesLeadingInteriorAndTrailingSpaces() {
        let result = formatter.format(
            rows: [
                "aa  xx  end",
                "bb    y end",
                "cc  zz  end"
            ],
            rows: 0..<3,
            columns: 4..<8
        )

        XCTAssertEqual(result.plainText, "xx  \n  y \nzz  ")
    }

    func testPadsShortLinesInsideTheRectangle() {
        let result = formatter.format(
            rows: [
                "abcdef",
                "abc",
                "abcdefgh"
            ],
            rows: 0..<3,
            columns: 2..<7
        )

        XCTAssertEqual(result.plainText, "cdef \nc    \ncdefg")
    }

    func testNormalizesSourceLineEndingsToLFOutput() {
        let result = formatter.format(
            text: "aa11\r\nbb22\rcc33\n",
            rows: 0..<3,
            columns: 2..<4
        )

        XCTAssertEqual(result.plainText, "11\n22\n33")
    }

    func testPadsRowsThatStartPastLineEnd() {
        let result = formatter.format(
            rows: [
                "left",
                "middle",
                "right"
            ],
            rows: 0..<3,
            columns: 6..<10
        )

        XCTAssertEqual(result.plainText, "    \n    \n    ")
    }

    func testReturnsNoOutputForEmptySelections() {
        let rows = ["abc", "def"]

        XCTAssertEqual(formatter.format(rows: rows, rows: 0..<0, columns: 0..<2), .noOutput)
        XCTAssertEqual(formatter.format(rows: rows, rows: 0..<1, columns: 2..<2), .noOutput)
        XCTAssertEqual(formatter.format(rows: rows, rows: 4..<6, columns: 0..<2), .noOutput)
        XCTAssertEqual(formatter.format(text: "", rows: 0..<1, columns: 0..<2), .noOutput)
    }

    func testFormatsExistingTerminalFixtureRange() {
        let result = formatter.format(
            rows: [
                "$ ps -o pid,tty,time,command",
                "  PID TTY           TIME COMMAND",
                " 1041 ttys000    0:00.28 zsh",
                " 1188 ttys000    0:01.52 swift build",
                " 1302 ttys001    0:00.09 vim README.md",
                " 1433 ttys002    0:02.31 tail -f app.log"
            ],
            rows: 2..<6,
            columns: 6..<24
        )

        XCTAssertEqual(
            result.plainText,
            "ttys000    0:00.28\nttys000    0:01.52\nttys001    0:00.09\nttys002    0:02.31"
        )
    }

    func testFormatsExistingEditorFixtureRange() {
        let result = formatter.format(
            rows: [
                "Name        Q1   Q2   Q3   Q4",
                "alpha       12   15   18   22",
                "bravo        9   14   17   19",
                "charlie     20   21   23   25",
                "delta       11   13   16   18"
            ],
            rows: 0..<5,
            columns: 17..<24
        )

        XCTAssertEqual(result.plainText, "Q2   Q3\n15   18\n14   17\n21   23\n13   16")
    }
}
