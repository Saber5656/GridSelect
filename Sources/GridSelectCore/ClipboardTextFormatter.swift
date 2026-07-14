import Foundation

public struct ClipboardTextFormatter: Equatable, Sendable {
    public init() {}

    /// Normalizes an already rectangular extraction for the pasteboard boundary.
    /// Coordinate mapping owns column padding; this step owns line endings and
    /// the no-final-newline clipboard contract.
    public func formatExtractedText(_ text: String) -> ClipboardTextFormattingResult {
        guard !text.isEmpty else {
            return .noOutput
        }

        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        while normalized.last == "\n" {
            normalized.removeLast()
        }

        guard !normalized.isEmpty else {
            return .noOutput
        }
        return .plainText(normalized)
    }

    public func format(
        text: String,
        rows rowRange: Range<Int>,
        columns columnRange: Range<Int>
    ) -> ClipboardTextFormattingResult {
        // Use the rows overload to represent a selected row that is intentionally empty.
        guard !text.isEmpty else {
            return .noOutput
        }

        return format(
            rows: Self.logicalRows(from: text),
            rows: rowRange,
            columns: columnRange
        )
    }

    public func format(
        rows sourceRows: [String],
        rows rowRange: Range<Int>,
        columns columnRange: Range<Int>
    ) -> ClipboardTextFormattingResult {
        let lowerRow = max(0, rowRange.lowerBound)
        let upperRow = min(sourceRows.count, rowRange.upperBound)
        let lowerColumn = max(0, columnRange.lowerBound)
        let upperColumn = max(0, columnRange.upperBound)

        guard lowerRow < upperRow, lowerColumn < upperColumn else {
            return .noOutput
        }

        let width = upperColumn - lowerColumn
        let formattedRows = sourceRows[lowerRow..<upperRow]
            .map { Self.sliceAndPadLine($0, start: lowerColumn, width: width) }

        return .plainText(formattedRows.joined(separator: "\n"))
    }

    private static func logicalRows(from text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private static func sliceAndPadLine(_ line: String, start: Int, width: Int) -> String {
        guard width > 0 else {
            return ""
        }

        guard let startIndex = line.index(line.startIndex, offsetBy: start, limitedBy: line.endIndex) else {
            return String(repeating: " ", count: width)
        }

        let endIndex = line.index(startIndex, offsetBy: width, limitedBy: line.endIndex) ?? line.endIndex
        let selected = String(line[startIndex..<endIndex])
        let missingWidth = width - selected.count

        guard missingWidth > 0 else {
            return selected
        }

        return selected + String(repeating: " ", count: missingWidth)
    }
}

public enum ClipboardTextFormattingResult: Equatable, Sendable {
    case noOutput
    case plainText(String)

    public var plainText: String? {
        guard case let .plainText(value) = self else {
            return nil
        }

        return value
    }
}
