import Foundation

public struct GridActivation: Equatable, Sendable {
    public let generation: UInt64

    public init(generation: UInt64) {
        self.generation = generation
    }
}

public enum GridDirection: Equatable, Hashable, Sendable {
    case left
    case right
    case up
    case down
}

public enum GridHandoffCommand: Equatable, Sendable {
    case move(GridDirection)
    case copyRequested
    case cancelRequested
    case freeze
}

public enum GridGuardedKey: Equatable, Hashable, Sendable {
    case arrow(GridDirection)
    case commandC
    case escape
    case other
}

public enum GridActivationCancellationReason: Equatable, Sendable {
    case ordinaryKey
    case timedOut
    case queueOverflow
    case setupFailed
    case listenerDisabled
}

public enum GridInputEffect: Equatable, Sendable {
    case activated(GridActivation)
    case handoffCancelled(GridActivation, GridActivationCancellationReason)
    case listenerDisabled(GridActivation?)
}

public struct GridInputDisposition: Equatable, Sendable {
    public enum Delivery: Equatable, Sendable {
        case passThrough
        case consume
    }

    public let delivery: Delivery
    public let effect: GridInputEffect?

    public init(delivery: Delivery, effect: GridInputEffect? = nil) {
        self.delivery = delivery
        self.effect = effect
    }

    public static let passThrough = GridInputDisposition(delivery: .passThrough)
    public static let consume = GridInputDisposition(delivery: .consume)
}

/// Pure, content-independent state for modifier activation and the bounded
/// activation-to-overlay handoff. Callers classify virtual keys only while
/// `requiresGuardedKeyClassification` is true.
public struct GridActivationInputMachine: Equatable, Sendable {
    public static let handoffQueueCapacity = 32
    public static let handoffTimeout: TimeInterval = 0.5

    private enum GesturePhase: Equatable, Sendable {
        case idle
        case firstShiftDown(at: TimeInterval)
        case waitingForSecondShift(firstDownAt: TimeInterval)
    }

    private struct Handoff: Equatable, Sendable {
        let activation: GridActivation
        let deadline: TimeInterval
        var commands: [GridHandoffCommand]
        var freezeQueued: Bool
    }

    private let doubleClickInterval: TimeInterval
    private var gesturePhase: GesturePhase = .idle
    private var shiftIsDown = false
    private var nextGeneration: UInt64 = 0
    private var handoff: Handoff?

    public init(doubleClickInterval: TimeInterval) {
        self.doubleClickInterval = max(0, doubleClickInterval)
    }

    public var requiresGuardedKeyClassification: Bool {
        handoff != nil
    }

    public var activeHandoff: GridActivation? {
        handoff?.activation
    }

    public mutating func handleShiftChange(
        isDown: Bool,
        timestamp: TimeInterval
    ) -> GridInputDisposition {
        guard isDown != shiftIsDown else {
            return .passThrough
        }
        shiftIsDown = isDown

        if handoff != nil {
            guard !isDown else {
                return .passThrough
            }
            return enqueueFreeze(timestamp: timestamp)
        }

        if isDown {
            switch gesturePhase {
            case .idle:
                gesturePhase = .firstShiftDown(at: timestamp)
            case let .waitingForSecondShift(firstDownAt):
                guard timestamp >= firstDownAt,
                      timestamp - firstDownAt <= doubleClickInterval
                else {
                    gesturePhase = .firstShiftDown(at: timestamp)
                    return .passThrough
                }
                nextGeneration &+= 1
                let activation = GridActivation(generation: nextGeneration)
                handoff = Handoff(
                    activation: activation,
                    deadline: timestamp + Self.handoffTimeout,
                    commands: [],
                    freezeQueued: false
                )
                gesturePhase = .idle
                return GridInputDisposition(
                    delivery: .passThrough,
                    effect: .activated(activation)
                )
            case .firstShiftDown:
                break
            }
        } else if case let .firstShiftDown(firstDownAt) = gesturePhase {
            gesturePhase = .waitingForSecondShift(firstDownAt: firstDownAt)
        }

        return .passThrough
    }

    /// Content-blind invalidation used outside the handoff. The adapter must not
    /// read the key code or characters before calling this method.
    public mutating func handleUnclassifiedKeyDown() -> GridInputDisposition {
        guard let handoff else {
            gesturePhase = .idle
            return .passThrough
        }
        self.handoff = nil
        gesturePhase = .idle
        return GridInputDisposition(
            delivery: .passThrough,
            effect: .handoffCancelled(handoff.activation, .ordinaryKey)
        )
    }

    /// Handles a transient virtual-key classification while the handoff guard is
    /// active. No raw event or character data enters this model.
    public mutating func handleGuardedKeyDown(
        _ key: GridGuardedKey,
        timestamp: TimeInterval
    ) -> GridInputDisposition {
        guard let current = handoff else {
            gesturePhase = .idle
            return .passThrough
        }
        if timestamp > current.deadline {
            handoff = nil
            gesturePhase = .idle
            let delivery: GridInputDisposition.Delivery
            if case .other = key {
                delivery = .passThrough
            } else {
                delivery = .consume
            }
            return GridInputDisposition(
                delivery: delivery,
                effect: .handoffCancelled(current.activation, .timedOut)
            )
        }

        let command: GridHandoffCommand
        switch key {
        case let .arrow(direction):
            command = .move(direction)
        case .commandC:
            command = .copyRequested
        case .escape:
            command = .cancelRequested
        case .other:
            handoff = nil
            gesturePhase = .idle
            return GridInputDisposition(
                delivery: .passThrough,
                effect: .handoffCancelled(current.activation, .ordinaryKey)
            )
        }

        return enqueue(command, passThrough: false)
    }

    public mutating func completeHandoff(
        for activation: GridActivation,
        timestamp: TimeInterval
    ) -> [GridHandoffCommand]? {
        guard let current = handoff,
              current.activation == activation
        else {
            return nil
        }
        guard timestamp <= current.deadline else {
            handoff = nil
            gesturePhase = .idle
            return nil
        }
        handoff = nil
        return current.commands
    }

    public mutating func cancelHandoff(
        for activation: GridActivation,
        reason: GridActivationCancellationReason
    ) -> GridInputEffect? {
        guard handoff?.activation == activation else {
            return nil
        }
        handoff = nil
        gesturePhase = .idle
        return .handoffCancelled(activation, reason)
    }

    public mutating func expireHandoff(
        for activation: GridActivation,
        timestamp: TimeInterval
    ) -> GridInputEffect? {
        guard let current = handoff,
              current.activation == activation,
              timestamp > current.deadline
        else {
            return nil
        }
        handoff = nil
        gesturePhase = .idle
        return .handoffCancelled(activation, .timedOut)
    }

    public mutating func disableListener() -> GridInputEffect {
        gesturePhase = .idle
        shiftIsDown = false
        let activation = handoff?.activation
        handoff = nil
        return .listenerDisabled(activation)
    }

    private mutating func enqueueFreeze(timestamp: TimeInterval) -> GridInputDisposition {
        guard let current = handoff else {
            return .passThrough
        }
        if timestamp > current.deadline {
            handoff = nil
            gesturePhase = .idle
            return GridInputDisposition(
                delivery: .passThrough,
                effect: .handoffCancelled(current.activation, .timedOut)
            )
        }
        guard !current.freezeQueued else {
            return .passThrough
        }
        return enqueue(.freeze, passThrough: true)
    }

    private mutating func enqueue(
        _ command: GridHandoffCommand,
        passThrough: Bool
    ) -> GridInputDisposition {
        guard var current = handoff else {
            return .passThrough
        }
        guard current.commands.count < Self.handoffQueueCapacity else {
            handoff = nil
            gesturePhase = .idle
            return GridInputDisposition(
                delivery: passThrough ? .passThrough : .consume,
                effect: .handoffCancelled(current.activation, .queueOverflow)
            )
        }
        current.commands.append(command)
        if command == .freeze {
            current.freezeQueued = true
        }
        handoff = current
        return GridInputDisposition(
            delivery: passThrough ? .passThrough : .consume
        )
    }
}
