public enum GridOverlayInteractionEffect: Equatable, Sendable {
    case selectionChanged(SelectionRectangle)
    case selectionFrozen(SelectionRectangle)
    case selectAtLeastOneColumn
    case copyRequested(
        SelectionRectangle,
        BoundSelectionContext,
        GridCopyAuthorization
    )
    case cancelled
}

public enum GridMouseSelectionStartResult: Equatable, Sendable {
    case accepted(GridOverlayInteractionEffect)
    case ignored
    case rejected
}

public struct GridOverlaySessionGuard: Equatable, Sendable {
    private var nextGeneration: UInt64 = 0
    public private(set) var activeGeneration: UInt64?
    public private(set) var activeMouseDisplayID: UInt32?

    public init() {}

    public mutating func begin() -> UInt64 {
        nextGeneration &+= 1
        activeGeneration = nextGeneration
        activeMouseDisplayID = nil
        return nextGeneration
    }

    public func isCurrent(_ generation: UInt64) -> Bool {
        activeGeneration == generation
    }

    @discardableResult
    public mutating func beginMouseDrag(
        displayID: UInt32,
        generation: UInt64
    ) -> Bool {
        guard isCurrent(generation) else {
            return false
        }
        activeMouseDisplayID = displayID
        return true
    }

    public func acceptsMouseEvent(displayID: UInt32, generation: UInt64) -> Bool {
        isCurrent(generation) && activeMouseDisplayID == displayID
    }

    public mutating func endMouseDrag(generation: UInt64) {
        guard isCurrent(generation) else {
            return
        }
        activeMouseDisplayID = nil
    }

    public mutating func invalidateCurrent() {
        activeGeneration = nil
        activeMouseDisplayID = nil
    }
}

/// Pure interaction adapter shared by the AppKit keyboard and mouse paths.
public struct GridOverlayInteraction: Equatable, Sendable {
    public let sourceContext: ActivationSourceContext
    public private(set) var binder: GridSelectionContextBinder
    public private(set) var lifecycle: GridSelectionLifecycle

    public init(sourceContext: ActivationSourceContext) {
        self.sourceContext = sourceContext
        binder = GridSelectionContextBinder(activationContext: sourceContext)
        lifecycle = GridSelectionLifecycle()
        _ = lifecycle.begin(sourceContext.activation)
        bindKeyboardCaretIfUsable()
    }

    public var currentRectangle: SelectionRectangle? {
        guard let selection = currentSelection,
              let viewport = binder.boundContext?.viewport
        else {
            return nil
        }
        return viewport.rectangle(for: selection)
    }

    public mutating func moveKeyboardFocus(
        _ direction: GridDirection
    ) -> GridOverlayInteractionEffect? {
        guard let selection = currentSelection,
              let context = binder.boundContext,
              let viewport = context.viewport,
              let maximumColumn = viewport.maximumColumn(within: context.display.appKitFrame)
        else {
            return nil
        }
        if direction == .down, selection.focus.row >= viewport.visualRowCount - 1 {
            return nil
        }
        if direction == .right, selection.focus.column >= maximumColumn {
            return nil
        }
        return translate(lifecycle.moveKeyboardFocus(direction))
    }

    public mutating func beginMouseSelection(
        candidate: GridMouseAnchorCandidate,
        at point: SelectionPoint
    ) -> GridMouseSelectionStartResult {
        guard candidate.viewport.isUsable,
              let anchor = candidate.viewport.boundary(
                  at: point,
                  role: .initialAnchor
              ),
              let display = sourceContext.displays.first(where: {
                  $0.displayID == candidate.viewport.displayID
              }),
              let maximumColumn = candidate.viewport.maximumColumn(
                  within: display.appKitFrame
              )
        else {
            return .rejected
        }

        let boundedAnchor = GridBoundary(
            row: anchor.row,
            column: min(anchor.column, maximumColumn)
        )

        if let bound = binder.boundContext {
            let matchesBoundContext = bound.source == candidate.source
                && bound.element == candidate.element
                && bound.display.displayID == candidate.viewport.displayID
                && bound.viewport == candidate.viewport
            let mayReanchor: Bool
            switch lifecycle.state {
            case let .adjusting(_, selection), let .selected(_, selection):
                mayReanchor = selection.isEmpty
            default:
                mayReanchor = false
            }
            guard mayReanchor else {
                return matchesBoundContext ? .ignored : .rejected
            }
            guard case .bound = binder.rebindMouseAnchor(
                      source: candidate.source,
                      element: candidate.element,
                      anchor: boundedAnchor,
                      sourceRange: candidate.sourceRange,
                      displayID: candidate.viewport.displayID,
                      viewport: candidate.viewport
                  ) else {
                return .rejected
            }
        } else {
            guard case .bound = binder.bindMouseAnchor(
                source: candidate.source,
                element: candidate.element,
                anchor: boundedAnchor,
                sourceRange: candidate.sourceRange,
                displayID: candidate.viewport.displayID,
                viewport: candidate.viewport
            ) else {
                return .rejected
            }
        }

        guard let effect = translate(lifecycle.beginMouseSelection(at: boundedAnchor)) else {
            return .ignored
        }
        return .accepted(effect)
    }

    public mutating func moveMouseFocus(
        to point: SelectionPoint
    ) -> GridOverlayInteractionEffect? {
        guard let selection = currentSelection,
              let context = binder.boundContext,
              let viewport = context.viewport,
              let maximumColumn = viewport.maximumColumn(within: context.display.appKitFrame),
              let snappedFocus = viewport.boundary(
                  at: clamped(point, to: context.display.appKitFrame),
                  role: .focus(anchorColumn: selection.anchor.column)
              )
        else {
            return nil
        }
        let focus = GridBoundary(
            row: snappedFocus.row,
            column: min(snappedFocus.column, maximumColumn)
        )
        return translate(lifecycle.moveMouseFocus(to: focus))
    }

    public mutating func freeze() -> GridOverlayInteractionEffect? {
        translate(lifecycle.freeze())
    }

    public mutating func requestCopy() -> GridOverlayInteractionEffect? {
        translate(lifecycle.requestCopy())
    }

    public mutating func cancel() -> GridOverlayInteractionEffect? {
        translate(lifecycle.cancel())
    }

    @discardableResult
    public mutating func finishCopy(
        _ authorization: GridCopyAuthorization,
        succeeded: Bool
    ) -> Bool {
        switch lifecycle.finishCopy(authorization, succeeded: succeeded) {
        case .completed, .failed:
            return true
        case .staleResultDiscarded:
            return false
        case .selectionChanged, .selectionFrozen, .selectAtLeastOneColumn,
             .copyStarted, .copyRequestConsumed, .cancelled:
            return false
        }
    }

    @discardableResult
    public mutating func cancelCopy(
        _ authorization: GridCopyAuthorization
    ) -> Bool {
        guard case let .copying(current) = lifecycle.state,
              current == authorization,
              lifecycle.cancel() == .cancelled
        else {
            return false
        }
        return true
    }

    public mutating func applyHandoffCommands(
        _ commands: [GridHandoffCommand]
    ) -> [GridOverlayInteractionEffect] {
        var effects: [GridOverlayInteractionEffect] = []
        for command in commands {
            let effect: GridOverlayInteractionEffect?
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
            switch effect {
            case .cancelled:
                return effects
            default:
                break
            }
        }
        return effects
    }

    private var currentSelection: GridIndexSelection? {
        switch lifecycle.state {
        case let .adjusting(_, selection), let .selected(_, selection):
            return selection
        case let .copying(authorization):
            return authorization.selection
        case .inactive, .armed, .completed, .cancelled, .failed:
            return nil
        }
    }

    private mutating func bindKeyboardCaretIfUsable() {
        guard sourceContext.caretCandidate?.viewport?.isUsable == true,
              case let .bound(context) = binder.bindKeyboardCaret()
        else {
            return
        }
        _ = lifecycle.bindKeyboardAnchor(context.anchor)
    }

    private func translate(
        _ effect: GridSelectionLifecycleEffect?
    ) -> GridOverlayInteractionEffect? {
        guard let effect else {
            return nil
        }
        switch effect {
        case let .selectionChanged(selection):
            return rectangle(for: selection).map(GridOverlayInteractionEffect.selectionChanged)
        case let .selectionFrozen(selection):
            return rectangle(for: selection).map(GridOverlayInteractionEffect.selectionFrozen)
        case .selectAtLeastOneColumn:
            return .selectAtLeastOneColumn
        case let .copyStarted(authorization):
            guard let rectangle = rectangle(for: authorization.selection),
                  let context = binder.boundContext
            else {
                return nil
            }
            return .copyRequested(rectangle, context, authorization)
        case .cancelled:
            return .cancelled
        case .copyRequestConsumed, .staleResultDiscarded, .completed, .failed:
            return nil
        }
    }

    private func rectangle(for selection: GridIndexSelection) -> SelectionRectangle? {
        binder.boundContext?.viewport?.rectangle(for: selection)
    }

    private func clamped(
        _ point: SelectionPoint,
        to frame: ScreenRectangle
    ) -> SelectionPoint {
        SelectionPoint(
            x: min(max(point.x, frame.minX), frame.maxX),
            y: min(max(point.y, frame.minY), frame.maxY)
        )
    }
}
