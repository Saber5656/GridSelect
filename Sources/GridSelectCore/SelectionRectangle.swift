public struct SelectionRectangle: Equatable, Sendable {
    public let displayID: UInt32
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(
        displayID: UInt32,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) {
        self.displayID = displayID
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var isEmpty: Bool {
        width <= 0 || height <= 0
    }
}
