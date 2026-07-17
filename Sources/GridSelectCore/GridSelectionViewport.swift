public enum GridPointerBoundaryRole: Equatable, Sendable {
    case initialAnchor
    case focus(anchorColumn: Int)
}

/// Stable screen-point geometry for one visible monospace text grid.
///
/// `originX` and `topY` are global AppKit screen points. Rows grow downward
/// from `topY`; emitted `SelectionRectangle` values remain in AppKit's
/// bottom-left global screen space.
public struct GridSelectionViewport: Equatable, Sendable {
    private static let tieEpsilon = 1e-9

    public let displayID: UInt32
    public let originX: Double
    public let topY: Double
    public let characterWidth: Double
    public let lineHeight: Double
    public let visualRowCount: Int

    public init(
        displayID: UInt32,
        originX: Double,
        topY: Double,
        characterWidth: Double,
        lineHeight: Double,
        visualRowCount: Int
    ) {
        self.displayID = displayID
        self.originX = originX
        self.topY = topY
        self.characterWidth = characterWidth
        self.lineHeight = lineHeight
        self.visualRowCount = max(0, visualRowCount)
    }

    public var isUsable: Bool {
        originX.isFinite
            && topY.isFinite
            && characterWidth.isFinite
            && lineHeight.isFinite
            && characterWidth > 0
            && lineHeight > 0
            && visualRowCount > 0
    }

    /// Returns the last grid boundary whose x-coordinate remains inside `frame`.
    public func maximumColumn(within frame: ScreenRectangle) -> Int? {
        guard isUsable, frame.maxX.isFinite else {
            return nil
        }
        let horizontalSpan = frame.maxX - originX
        guard horizontalSpan >= 0 else {
            return nil
        }
        let column = (horizontalSpan / characterWidth).rounded(.down)
        guard column.isFinite, column < Double(Int.max) else {
            return nil
        }
        return Int(column)
    }

    public func boundary(
        at point: SelectionPoint,
        role: GridPointerBoundaryRole
    ) -> GridBoundary? {
        guard isUsable, point.x.isFinite, point.y.isFinite else {
            return nil
        }

        let cellPosition = max(0, (point.x - originX) / characterWidth)
        guard cellPosition.isFinite, cellPosition < Double(Int.max - 1) else {
            return nil
        }
        let lower = Int(cellPosition.rounded(.down))
        let fraction = cellPosition - Double(lower)
        let column: Int
        if fraction < 0.5 - Self.tieEpsilon {
            column = lower
        } else if fraction > 0.5 + Self.tieEpsilon {
            column = lower + 1
        } else {
            switch role {
            case .initialAnchor:
                column = lower + 1
            case let .focus(anchorColumn):
                let upper = lower + 1
                column = abs(lower - anchorColumn) > abs(upper - anchorColumn)
                    ? lower
                    : upper
            }
        }

        let rowPosition = (topY - point.y) / lineHeight
        guard rowPosition.isFinite else {
            return nil
        }
        let unclampedRow: Int
        if rowPosition <= 0 {
            unclampedRow = 0
        } else if rowPosition >= Double(Int.max - 1) {
            unclampedRow = Int.max - 1
        } else {
            unclampedRow = Int(rowPosition.rounded(.down))
        }
        let row = min(max(0, unclampedRow), visualRowCount - 1)
        return GridBoundary(row: row, column: column)
    }

    public func rectangle(for selection: GridIndexSelection) -> SelectionRectangle? {
        guard isUsable,
              selection.rowRange.lowerBound < visualRowCount,
              selection.columnRange.upperBound < Int.max
        else {
            return nil
        }

        let rowStart = min(selection.rowRange.lowerBound, visualRowCount - 1)
        let rowEnd = min(selection.rowRange.upperBound, visualRowCount)
        guard rowStart < rowEnd else {
            return nil
        }

        let x = originX + Double(selection.columnRange.lowerBound) * characterWidth
        let top = topY - Double(rowStart) * lineHeight
        let bottom = topY - Double(rowEnd) * lineHeight
        let width = Double(selection.columnRange.count) * characterWidth
        let height = top - bottom
        guard x.isFinite, bottom.isFinite, width.isFinite, height.isFinite else {
            return nil
        }
        return SelectionRectangle(
            displayID: displayID,
            x: x,
            y: bottom,
            width: width,
            height: height
        )
    }
}
