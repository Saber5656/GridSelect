public struct SelectionPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct SelectionDragGeometry: Equatable, Sendable {
    public let displayID: UInt32
    public let screenOrigin: SelectionPoint
    public let screenWidth: Double
    public let screenHeight: Double
    public let minimumSelectionSize: Double

    public init(
        displayID: UInt32,
        screenOrigin: SelectionPoint,
        screenWidth: Double,
        screenHeight: Double,
        minimumSelectionSize: Double = 4
    ) {
        self.displayID = displayID
        self.screenOrigin = screenOrigin
        self.screenWidth = max(0, screenWidth)
        self.screenHeight = max(0, screenHeight)
        self.minimumSelectionSize = max(0, minimumSelectionSize)
    }

    public func rectangle(
        from anchor: SelectionPoint,
        to current: SelectionPoint
    ) -> SelectionRectangle {
        let start = clamped(anchor)
        let end = clamped(current)

        return SelectionRectangle(
            displayID: displayID,
            x: screenOrigin.x + min(start.x, end.x),
            y: screenOrigin.y + min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }

    public func isConfirmable(_ rectangle: SelectionRectangle) -> Bool {
        rectangle.displayID == displayID
            && rectangle.width >= minimumSelectionSize
            && rectangle.height >= minimumSelectionSize
    }

    private func clamped(_ point: SelectionPoint) -> SelectionPoint {
        SelectionPoint(
            x: min(max(point.x, 0), screenWidth),
            y: min(max(point.y, 0), screenHeight)
        )
    }
}
