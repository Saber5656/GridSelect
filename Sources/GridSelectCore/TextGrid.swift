public struct TextGrid: Equatable, Sendable {
    public let rows: [String]

    public init(rows: [String]) {
        self.rows = rows
    }

    public func slice(rows rowRange: Range<Int>, columns columnRange: Range<Int>) -> String {
        let lowerRow = max(0, rowRange.lowerBound)
        let upperRow = min(rows.count, rowRange.upperBound)
        guard lowerRow < upperRow else {
            return ""
        }

        return rows[lowerRow..<upperRow]
            .map { Self.sliceLine($0, columns: columnRange) }
            .joined(separator: "\n")
    }

    private static func sliceLine(_ line: String, columns columnRange: Range<Int>) -> String {
        let lowerColumn = max(0, columnRange.lowerBound)
        let upperColumn = max(0, columnRange.upperBound)
        guard lowerColumn < upperColumn else {
            return ""
        }

        guard let start = line.index(line.startIndex, offsetBy: lowerColumn, limitedBy: line.endIndex) else {
            return ""
        }

        let end = line.index(line.startIndex, offsetBy: upperColumn, limitedBy: line.endIndex) ?? line.endIndex
        return String(line[start..<end])
    }
}
