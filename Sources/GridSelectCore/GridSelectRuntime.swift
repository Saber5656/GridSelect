public struct GridSelectRuntime: Equatable, Sendable {
    public let name: String
    public let status: RuntimeStatus

    public init(
        name: String = "GridSelect",
        status: RuntimeStatus = .scaffoldReady
    ) {
        self.name = name
        self.status = status
    }

    public var statusText: String {
        status.rawValue
    }
}

public enum RuntimeStatus: String, Equatable, Sendable {
    case scaffoldReady = "Pre-alpha scaffold"
}
