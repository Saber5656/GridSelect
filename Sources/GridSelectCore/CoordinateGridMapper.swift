import Foundation

public struct ScreenRectangle: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

public struct DisplayGeometry: Equatable, Sendable {
    public let displayID: UInt32
    public let appKitFrame: ScreenRectangle
    public let coreGraphicsBounds: ScreenRectangle
    public let backingScale: Double

    public init(
        displayID: UInt32,
        appKitFrame: ScreenRectangle,
        coreGraphicsBounds: ScreenRectangle,
        backingScale: Double
    ) {
        self.displayID = displayID
        self.appKitFrame = appKitFrame
        self.coreGraphicsBounds = coreGraphicsBounds
        self.backingScale = backingScale
    }

    public func canonicalRectangle(for selection: SelectionRectangle) -> ScreenRectangle? {
        guard selection.displayID == displayID,
              !selection.isEmpty,
              appKitFrame.width > 0,
              appKitFrame.height > 0
        else {
            return nil
        }

        return ScreenRectangle(
            x: coreGraphicsBounds.minX + (selection.x - appKitFrame.minX),
            y: coreGraphicsBounds.minY + (appKitFrame.maxY - (selection.y + selection.height)),
            width: selection.width,
            height: selection.height
        )
    }
}

public struct TextGridGeometry: Equatable, Sendable {
    public let originX: Double
    public let originY: Double
    public let characterWidth: Double
    public let lineHeight: Double

    public init(originX: Double, originY: Double, characterWidth: Double, lineHeight: Double) {
        self.originX = originX
        self.originY = originY
        self.characterWidth = characterWidth
        self.lineHeight = lineHeight
    }
}

public struct VisualLine: Equatable, Sendable {
    public let text: String
    public let sourceLocation: Int?
    public let sourceLength: Int?
    public let isSoftWrapped: Bool

    public init(
        text: String,
        sourceLocation: Int? = nil,
        sourceLength: Int? = nil,
        isSoftWrapped: Bool = false
    ) {
        self.text = text
        self.sourceLocation = sourceLocation
        self.sourceLength = sourceLength
        self.isSoftWrapped = isSoftWrapped
    }
}

public struct GridMappingPolicy: Equatable, Sendable {
    public let tabStop: Int?
    public let maximumOutputCells: Int

    public init(tabStop: Int? = nil, maximumOutputCells: Int = 100_000) {
        self.tabStop = tabStop.flatMap { $0 > 0 ? $0 : nil }
        self.maximumOutputCells = max(1, maximumOutputCells)
    }
}

public enum GridMappingDiagnostic: Equatable, Sendable {
    case clampedLeft
    case rightPadded
    case tabExpanded
    case softWrappedVisualRow
    case retinaPoints(backingScale: Double)
}

public enum GridMappingUnsupportedReason: Error, Equatable, Sendable {
    case displayMismatch
    case invalidGeometry
    case tabStopUnknown
    case variableWidthContent
    case combiningCharacterContent
    case selectionTooLarge
}

public struct GridSelectedRow: Equatable, Sendable {
    public let visualRowIndex: Int
    public let sourceLocation: Int?
    public let sourceLength: Int?
    public let gridText: String
    public let missingCellCount: Int
    public let normalizations: [GridMappingDiagnostic]

    public init(
        visualRowIndex: Int,
        sourceLocation: Int?,
        sourceLength: Int?,
        gridText: String,
        missingCellCount: Int,
        normalizations: [GridMappingDiagnostic]
    ) {
        self.visualRowIndex = visualRowIndex
        self.sourceLocation = sourceLocation
        self.sourceLength = sourceLength
        self.gridText = gridText
        self.missingCellCount = missingCellCount
        self.normalizations = normalizations
    }
}

public struct GridSelection: Equatable, Sendable {
    public let rowRange: Range<Int>
    public let columnRange: Range<Int>
    public let rows: [GridSelectedRow]
    public let diagnostics: [GridMappingDiagnostic]

    public init(
        rowRange: Range<Int>,
        columnRange: Range<Int>,
        rows: [GridSelectedRow],
        diagnostics: [GridMappingDiagnostic]
    ) {
        self.rowRange = rowRange
        self.columnRange = columnRange
        self.rows = rows
        self.diagnostics = diagnostics
    }

    public var plainText: String {
        rows.map(\.gridText).joined(separator: "\n")
    }
}

public enum GridMappingResult: Equatable, Sendable {
    case selection(GridSelection)
    case empty
    case unsupported(GridMappingUnsupportedReason)
}

public struct CoordinateGridMapper: Equatable, Sendable {
    private static let boundaryEpsilon = 1e-9

    public init() {}

    public func map(
        selection: SelectionRectangle,
        display: DisplayGeometry,
        grid: TextGridGeometry,
        visualLines: [VisualLine],
        policy: GridMappingPolicy = GridMappingPolicy()
    ) -> GridMappingResult {
        guard selection.displayID == display.displayID else {
            return .unsupported(.displayMismatch)
        }
        guard let canonical = display.canonicalRectangle(for: selection),
              canonical.minX.isFinite,
              canonical.minY.isFinite,
              canonical.maxX.isFinite,
              canonical.maxY.isFinite,
              grid.originX.isFinite,
              grid.originY.isFinite,
              grid.characterWidth.isFinite,
              grid.lineHeight.isFinite,
              grid.characterWidth > 0,
              grid.lineHeight > 0
        else {
            return .unsupported(.invalidGeometry)
        }
        guard !visualLines.isEmpty else {
            return .empty
        }

        let measuredBottom = grid.originY + (Double(visualLines.count) * grid.lineHeight)
        guard canonical.maxY > grid.originY, canonical.minY < measuredBottom else {
            return .empty
        }
        guard canonical.maxX > grid.originX else {
            return .empty
        }

        let rowStart = Self.boundedFloor(
            (canonical.minY - grid.originY) / grid.lineHeight,
            upper: visualLines.count
        )
        let rowEnd = max(
            rowStart,
            Self.boundedCeil(
                (canonical.maxY - grid.originY) / grid.lineHeight,
                upper: visualLines.count
            )
        )
        guard let columnStart = Self.nonnegativeFloor(
            (canonical.minX - grid.originX) / grid.characterWidth
        ),
        let requestedColumnEnd = Self.nonnegativeCeil(
            (canonical.maxX - grid.originX) / grid.characterWidth
        ) else {
            return .unsupported(.selectionTooLarge)
        }
        let columnEnd = max(columnStart, requestedColumnEnd)

        guard rowStart < rowEnd, columnStart < columnEnd else {
            return .empty
        }
        let width = columnEnd - columnStart
        let rowCount = rowEnd - rowStart
        guard width <= policy.maximumOutputCells,
              rowCount <= policy.maximumOutputCells / width
        else {
            return .unsupported(.selectionTooLarge)
        }

        var diagnostics: [GridMappingDiagnostic] = []
        if canonical.minX < grid.originX {
            diagnostics.append(.clampedLeft)
        }
        if display.backingScale > 1 {
            diagnostics.append(.retinaPoints(backingScale: display.backingScale))
        }

        var selectedRows: [GridSelectedRow] = []
        for rowIndex in rowStart..<rowEnd {
            let line = visualLines[rowIndex]
            let normalized: NormalizedLine
            switch Self.normalize(
                line.text,
                selecting: columnStart..<columnEnd,
                policy: policy
            ) {
            case let .success(value):
                normalized = value
            case let .failure(reason):
                return .unsupported(reason)
            }

            let copiedCount = normalized.cells.count
            let missingCount = width - copiedCount
            let copied = copiedCount > 0
                ? String(normalized.cells)
                : ""
            let gridText = copied + String(repeating: " ", count: missingCount)

            var rowDiagnostics = normalized.diagnostics
            if line.isSoftWrapped {
                rowDiagnostics.append(.softWrappedVisualRow)
            }
            if missingCount > 0 {
                rowDiagnostics.append(.rightPadded)
                if !diagnostics.contains(.rightPadded) {
                    diagnostics.append(.rightPadded)
                }
            }
            for diagnostic in rowDiagnostics where !diagnostics.contains(diagnostic) {
                diagnostics.append(diagnostic)
            }

            selectedRows.append(
                GridSelectedRow(
                    visualRowIndex: rowIndex,
                    sourceLocation: line.sourceLocation,
                    sourceLength: line.sourceLength,
                    gridText: gridText,
                    missingCellCount: missingCount,
                    normalizations: rowDiagnostics
                )
            )
        }

        return .selection(
            GridSelection(
                rowRange: rowStart..<rowEnd,
                columnRange: columnStart..<columnEnd,
                rows: selectedRows,
                diagnostics: diagnostics
            )
        )
    }

    private struct NormalizedLine {
        let cells: [Character]
        let diagnostics: [GridMappingDiagnostic]
    }

    private static func normalize(
        _ text: String,
        selecting columns: Range<Int>,
        policy: GridMappingPolicy
    ) -> Result<NormalizedLine, GridMappingUnsupportedReason> {
        var cells: [Character] = []
        var diagnostics: [GridMappingDiagnostic] = []
        var logicalColumn = 0
        for character in text {
            if logicalColumn >= columns.upperBound {
                break
            }
            if character.unicodeScalars.contains(where: {
                CharacterSet.nonBaseCharacters.contains($0)
            }) {
                return .failure(.combiningCharacterContent)
            }
            if character == "\t" {
                guard let tabStop = policy.tabStop else {
                    return .failure(.tabStopUnknown)
                }
                let spacesToNextStop = tabStop - (logicalColumn % tabStop)
                let consumedColumns = min(
                    spacesToNextStop,
                    columns.upperBound - logicalColumn
                )
                let tabEnd = logicalColumn + consumedColumns
                let selectedStart = max(logicalColumn, columns.lowerBound)
                if selectedStart < tabEnd {
                    cells.append(
                        contentsOf: repeatElement(" ", count: tabEnd - selectedStart)
                    )
                }
                if !diagnostics.contains(.tabExpanded) {
                    diagnostics.append(.tabExpanded)
                }
                logicalColumn = tabEnd
                continue
            }

            guard character.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7e }) else {
                return .failure(.variableWidthContent)
            }
            if logicalColumn >= columns.lowerBound {
                cells.append(character)
            }
            logicalColumn += 1
        }

        return .success(NormalizedLine(cells: cells, diagnostics: diagnostics))
    }

    private static func boundaryCeil(_ value: Double) -> Int {
        let nearest = value.rounded()
        if abs(value - nearest) <= boundaryEpsilon {
            return Int(nearest)
        }
        return Int(ceil(value))
    }

    private static func boundaryFloor(_ value: Double) -> Int {
        let nearest = value.rounded()
        if abs(value - nearest) <= boundaryEpsilon {
            return Int(nearest)
        }
        return Int(floor(value))
    }

    private static func boundedFloor(_ value: Double, upper: Int) -> Int {
        if value <= 0 {
            return 0
        }
        if value >= Double(upper) {
            return upper
        }
        return boundaryFloor(value)
    }

    private static func boundedCeil(_ value: Double, upper: Int) -> Int {
        if value <= 0 {
            return 0
        }
        if value >= Double(upper) {
            return upper
        }
        return boundaryCeil(value)
    }

    private static func nonnegativeFloor(_ value: Double) -> Int? {
        if value <= 0 {
            return 0
        }
        guard value.isFinite, value < Double(Int.max) else {
            return nil
        }
        return boundaryFloor(value)
    }

    private static func nonnegativeCeil(_ value: Double) -> Int? {
        if value <= 0 {
            return 0
        }
        guard value.isFinite, value < Double(Int.max) else {
            return nil
        }
        return boundaryCeil(value)
    }
}
