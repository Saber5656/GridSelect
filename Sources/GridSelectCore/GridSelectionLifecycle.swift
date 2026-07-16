public struct GridBoundary: Equatable, Sendable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = min(max(0, row), Int.max - 1)
        self.column = max(0, column)
    }
}

public struct GridIndexSelection: Equatable, Sendable {
    public let anchor: GridBoundary
    public private(set) var focus: GridBoundary

    public init(anchor: GridBoundary, focus: GridBoundary? = nil) {
        self.anchor = anchor
        self.focus = focus ?? anchor
    }

    public var rowRange: Range<Int> {
        let lower = min(anchor.row, focus.row)
        let upper = max(anchor.row, focus.row) + 1
        return lower..<upper
    }

    public var columnRange: Range<Int> {
        min(anchor.column, focus.column)..<max(anchor.column, focus.column)
    }

    public var isEmpty: Bool {
        columnRange.isEmpty
    }

    public mutating func moveFocus(_ direction: GridDirection) {
        switch direction {
        case .left:
            focus = GridBoundary(row: focus.row, column: max(0, focus.column - 1))
        case .right:
            focus = GridBoundary(
                row: focus.row,
                column: focus.column == Int.max ? Int.max : focus.column + 1
            )
        case .up:
            focus = GridBoundary(row: max(0, focus.row - 1), column: focus.column)
        case .down:
            focus = GridBoundary(
                row: focus.row == Int.max - 1 ? Int.max - 1 : focus.row + 1,
                column: focus.column
            )
        }
    }

    public mutating func moveFocus(to boundary: GridBoundary) {
        focus = boundary
    }
}

public struct GridCopyAuthorization: Equatable, Sendable {
    public let activation: GridActivation
    public let sequence: UInt64
    public let selection: GridIndexSelection

    public init(
        activation: GridActivation,
        sequence: UInt64,
        selection: GridIndexSelection
    ) {
        self.activation = activation
        self.sequence = sequence
        self.selection = selection
    }
}

public enum GridSelectionLifecycleState: Equatable, Sendable {
    case inactive
    case armed(GridActivation)
    case adjusting(GridActivation, GridIndexSelection)
    case selected(GridActivation, GridIndexSelection)
    case copying(GridCopyAuthorization)
    case completed(GridActivation)
    case cancelled(GridActivation)
    case failed(GridActivation)
}

public enum GridSelectionLifecycleEffect: Equatable, Sendable {
    case selectionChanged(GridIndexSelection)
    case selectionFrozen(GridIndexSelection)
    case selectAtLeastOneColumn
    case copyStarted(GridCopyAuthorization)
    case copyRequestConsumed
    case cancelled
    case staleResultDiscarded
    case completed
    case failed
}

public struct GridSelectionLifecycle: Equatable, Sendable {
    public private(set) var state: GridSelectionLifecycleState = .inactive
    private var nextCopySequence: UInt64 = 0

    public init() {}

    @discardableResult
    public mutating func begin(_ activation: GridActivation) -> Bool {
        guard !isActive else {
            return false
        }
        state = .armed(activation)
        return true
    }

    public mutating func bindKeyboardAnchor(
        _ anchor: GridBoundary
    ) -> GridSelectionLifecycleEffect? {
        guard case let .armed(activation) = state else {
            return nil
        }
        let selection = GridIndexSelection(anchor: anchor)
        state = .adjusting(activation, selection)
        return .selectionChanged(selection)
    }

    public mutating func beginMouseSelection(
        at anchor: GridBoundary
    ) -> GridSelectionLifecycleEffect? {
        let activation: GridActivation
        switch state {
        case let .armed(current):
            activation = current
        case let .adjusting(current, selection) where selection.isEmpty:
            activation = current
        case let .selected(current, selection) where selection.isEmpty:
            activation = current
        default:
            return nil
        }
        let selection = GridIndexSelection(anchor: anchor)
        state = .adjusting(activation, selection)
        return .selectionChanged(selection)
    }

    public mutating func moveKeyboardFocus(
        _ direction: GridDirection
    ) -> GridSelectionLifecycleEffect? {
        guard case let .adjusting(activation, current) = state else {
            return nil
        }
        var selection = current
        selection.moveFocus(direction)
        state = .adjusting(activation, selection)
        return .selectionChanged(selection)
    }

    public mutating func moveMouseFocus(
        to boundary: GridBoundary
    ) -> GridSelectionLifecycleEffect? {
        guard case let .adjusting(activation, current) = state else {
            return nil
        }
        var selection = current
        selection.moveFocus(to: boundary)
        state = .adjusting(activation, selection)
        return .selectionChanged(selection)
    }

    public mutating func freeze() -> GridSelectionLifecycleEffect? {
        guard case let .adjusting(activation, selection) = state else {
            return nil
        }
        state = .selected(activation, selection)
        return .selectionFrozen(selection)
    }

    public mutating func requestCopy() -> GridSelectionLifecycleEffect? {
        switch state {
        case let .selected(activation, selection):
            guard !selection.isEmpty else {
                return .selectAtLeastOneColumn
            }
            guard nextCopySequence < UInt64.max else {
                state = .failed(activation)
                return .failed
            }
            nextCopySequence += 1
            let authorization = GridCopyAuthorization(
                activation: activation,
                sequence: nextCopySequence,
                selection: selection
            )
            state = .copying(authorization)
            return .copyStarted(authorization)
        case .copying:
            return .copyRequestConsumed
        default:
            return nil
        }
    }

    public mutating func finishCopy(
        _ authorization: GridCopyAuthorization,
        succeeded: Bool
    ) -> GridSelectionLifecycleEffect {
        guard case let .copying(current) = state,
              current == authorization
        else {
            return .staleResultDiscarded
        }
        state = succeeded
            ? .completed(authorization.activation)
            : .failed(authorization.activation)
        return succeeded ? .completed : .failed
    }

    public mutating func cancel() -> GridSelectionLifecycleEffect? {
        guard isActive, let activation = currentActivation else {
            return nil
        }
        state = .cancelled(activation)
        return .cancelled
    }

    public mutating func applyHandoffCommands(
        _ commands: [GridHandoffCommand]
    ) -> [GridSelectionLifecycleEffect] {
        var effects: [GridSelectionLifecycleEffect] = []
        for command in commands {
            let effect: GridSelectionLifecycleEffect?
            switch command {
            case let .move(direction):
                effect = moveKeyboardFocus(direction)
            case .freeze:
                effect = freeze()
            case .copyRequested:
                effect = requestCopy()
            case .cancelRequested:
                effect = cancel()
            }
            if let effect {
                effects.append(effect)
            }
            if !isActive {
                break
            }
        }
        return effects
    }

    public var isActive: Bool {
        switch state {
        case .armed, .adjusting, .selected, .copying:
            return true
        case .inactive, .completed, .cancelled, .failed:
            return false
        }
    }

    private var currentActivation: GridActivation? {
        switch state {
        case let .armed(activation),
             let .adjusting(activation, _),
             let .selected(activation, _),
             let .completed(activation),
             let .cancelled(activation),
             let .failed(activation):
            return activation
        case let .copying(authorization):
            return authorization.activation
        case .inactive:
            return nil
        }
    }
}
