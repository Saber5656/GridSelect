public struct SelectionSourceIdentity: Equatable, Sendable {
    public let processIdentifier: Int32
    public let windowIdentifier: UInt32

    public init(processIdentifier: Int32, windowIdentifier: UInt32) {
        self.processIdentifier = processIdentifier
        self.windowIdentifier = windowIdentifier
    }
}

/// Opaque per-session token. The macOS adapter owns the AXUIElement handle and
/// must never derive this token from text, titles, or another logged value.
public struct SelectionElementIdentity: Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public struct GridCaretCandidate: Equatable, Sendable {
    public let element: SelectionElementIdentity
    public let anchor: GridBoundary
    public let sourceRange: Range<Int>
    public let displayID: UInt32

    public init(
        element: SelectionElementIdentity,
        anchor: GridBoundary,
        sourceRange: Range<Int>,
        displayID: UInt32
    ) {
        self.element = element
        self.anchor = anchor
        self.sourceRange = sourceRange
        self.displayID = displayID
    }
}

public struct ActivationSourceContext: Equatable, Sendable {
    public let activation: GridActivation
    public let source: SelectionSourceIdentity
    public let sourceWindowFrame: ScreenRectangle
    public let displays: [DisplayGeometry]
    public let caretCandidate: GridCaretCandidate?

    public init(
        activation: GridActivation,
        source: SelectionSourceIdentity,
        sourceWindowFrame: ScreenRectangle,
        displays: [DisplayGeometry],
        caretCandidate: GridCaretCandidate?
    ) {
        self.activation = activation
        self.source = source
        self.sourceWindowFrame = sourceWindowFrame
        self.displays = displays
        self.caretCandidate = caretCandidate
    }
}

public struct BoundSelectionContext: Equatable, Sendable {
    public let activation: GridActivation
    public let source: SelectionSourceIdentity
    public let element: SelectionElementIdentity
    public let anchor: GridBoundary
    public let sourceRange: Range<Int>
    public let display: DisplayGeometry

    public init(
        activation: GridActivation,
        source: SelectionSourceIdentity,
        element: SelectionElementIdentity,
        anchor: GridBoundary,
        sourceRange: Range<Int>,
        display: DisplayGeometry
    ) {
        self.activation = activation
        self.source = source
        self.element = element
        self.anchor = anchor
        self.sourceRange = sourceRange
        self.display = display
    }
}

public enum GridSelectionBindingFailure: Equatable, Sendable {
    case alreadyBound
    case caretUnavailable
    case sourceMismatch
    case displayUnavailable
}

public enum GridSelectionBindingResult: Equatable, Sendable {
    case bound(BoundSelectionContext)
    case rejected(GridSelectionBindingFailure)
}

public struct GridSelectionContextBinder: Equatable, Sendable {
    public let activationContext: ActivationSourceContext
    public private(set) var boundContext: BoundSelectionContext?

    public init(activationContext: ActivationSourceContext) {
        self.activationContext = activationContext
    }

    public mutating func bindKeyboardCaret() -> GridSelectionBindingResult {
        guard boundContext == nil else {
            return .rejected(.alreadyBound)
        }
        guard let candidate = activationContext.caretCandidate else {
            return .rejected(.caretUnavailable)
        }
        return bind(
            source: activationContext.source,
            element: candidate.element,
            anchor: candidate.anchor,
            sourceRange: candidate.sourceRange,
            displayID: candidate.displayID
        )
    }

    public mutating func bindMouseAnchor(
        source: SelectionSourceIdentity,
        element: SelectionElementIdentity,
        anchor: GridBoundary,
        sourceRange: Range<Int>,
        displayID: UInt32
    ) -> GridSelectionBindingResult {
        guard boundContext == nil else {
            return .rejected(.alreadyBound)
        }
        guard source == activationContext.source else {
            return .rejected(.sourceMismatch)
        }
        return bind(
            source: source,
            element: element,
            anchor: anchor,
            sourceRange: sourceRange,
            displayID: displayID
        )
    }

    private mutating func bind(
        source: SelectionSourceIdentity,
        element: SelectionElementIdentity,
        anchor: GridBoundary,
        sourceRange: Range<Int>,
        displayID: UInt32
    ) -> GridSelectionBindingResult {
        guard let display = activationContext.displays.first(where: {
            $0.displayID == displayID
        }) else {
            return .rejected(.displayUnavailable)
        }
        let context = BoundSelectionContext(
            activation: activationContext.activation,
            source: source,
            element: element,
            anchor: anchor,
            sourceRange: sourceRange,
            display: display
        )
        boundContext = context
        return .bound(context)
    }
}
