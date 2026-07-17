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

public struct SelectionSessionIdentity: Equatable, Hashable, Sendable {
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
    public let viewport: GridSelectionViewport?

    public init(
        element: SelectionElementIdentity,
        anchor: GridBoundary,
        sourceRange: Range<Int>,
        displayID: UInt32,
        viewport: GridSelectionViewport? = nil
    ) {
        self.element = element
        self.anchor = anchor
        self.sourceRange = sourceRange
        self.displayID = displayID
        self.viewport = viewport
    }
}

public struct GridMouseAnchorCandidate: Equatable, Sendable {
    public let source: SelectionSourceIdentity
    public let element: SelectionElementIdentity
    public let sourceRange: Range<Int>
    public let viewport: GridSelectionViewport

    public init(
        source: SelectionSourceIdentity,
        element: SelectionElementIdentity,
        sourceRange: Range<Int>,
        viewport: GridSelectionViewport
    ) {
        self.source = source
        self.element = element
        self.sourceRange = sourceRange
        self.viewport = viewport
    }
}

public struct ActivationSourceContext: Equatable, Sendable {
    public let activation: GridActivation
    public let sessionIdentity: SelectionSessionIdentity?
    public let source: SelectionSourceIdentity
    public let sourceWindowFrame: ScreenRectangle
    public let displays: [DisplayGeometry]
    public let caretCandidate: GridCaretCandidate?

    public init(
        activation: GridActivation,
        sessionIdentity: SelectionSessionIdentity? = nil,
        source: SelectionSourceIdentity,
        sourceWindowFrame: ScreenRectangle,
        displays: [DisplayGeometry],
        caretCandidate: GridCaretCandidate?
    ) {
        self.activation = activation
        self.sessionIdentity = sessionIdentity
        self.source = source
        self.sourceWindowFrame = sourceWindowFrame
        self.displays = displays
        self.caretCandidate = caretCandidate
    }
}

public enum SelectionBindingOrigin: Hashable, Sendable {
    case keyboardCaret
    case mouseHit
}

public struct BoundSelectionContext: Equatable, Sendable {
    public let activation: GridActivation
    public let sessionIdentity: SelectionSessionIdentity?
    public let source: SelectionSourceIdentity
    public let sourceWindowFrame: ScreenRectangle
    public let element: SelectionElementIdentity
    public let anchor: GridBoundary
    public let sourceRange: Range<Int>
    public let display: DisplayGeometry
    public let viewport: GridSelectionViewport?
    public let bindingOrigin: SelectionBindingOrigin

    public init(
        activation: GridActivation,
        sessionIdentity: SelectionSessionIdentity? = nil,
        source: SelectionSourceIdentity,
        sourceWindowFrame: ScreenRectangle,
        element: SelectionElementIdentity,
        anchor: GridBoundary,
        sourceRange: Range<Int>,
        display: DisplayGeometry,
        viewport: GridSelectionViewport? = nil,
        bindingOrigin: SelectionBindingOrigin = .keyboardCaret
    ) {
        self.activation = activation
        self.sessionIdentity = sessionIdentity
        self.source = source
        self.sourceWindowFrame = sourceWindowFrame
        self.element = element
        self.anchor = anchor
        self.sourceRange = sourceRange
        self.display = display
        self.viewport = viewport
        self.bindingOrigin = bindingOrigin
    }
}

public enum GridSelectionBindingFailure: Equatable, Sendable {
    case alreadyBound
    case caretUnavailable
    case sourceMismatch
    case displayUnavailable
    case invalidViewport
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
            displayID: candidate.displayID,
            viewport: candidate.viewport,
            bindingOrigin: .keyboardCaret
        )
    }

    public mutating func bindMouseAnchor(
        source: SelectionSourceIdentity,
        element: SelectionElementIdentity,
        anchor: GridBoundary,
        sourceRange: Range<Int>,
        displayID: UInt32,
        viewport: GridSelectionViewport? = nil
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
            displayID: displayID,
            viewport: viewport,
            bindingOrigin: .mouseHit
        )
    }

    public mutating func rebindMouseAnchor(
        source: SelectionSourceIdentity,
        element: SelectionElementIdentity,
        anchor: GridBoundary,
        sourceRange: Range<Int>,
        displayID: UInt32,
        viewport: GridSelectionViewport? = nil
    ) -> GridSelectionBindingResult {
        guard boundContext != nil else {
            return bindMouseAnchor(
                source: source,
                element: element,
                anchor: anchor,
                sourceRange: sourceRange,
                displayID: displayID,
                viewport: viewport
            )
        }
        let previous = boundContext
        boundContext = nil
        let result = bindMouseAnchor(
            source: source,
            element: element,
            anchor: anchor,
            sourceRange: sourceRange,
            displayID: displayID,
            viewport: viewport
        )
        if case .rejected = result {
            boundContext = previous
        }
        return result
    }

    private mutating func bind(
        source: SelectionSourceIdentity,
        element: SelectionElementIdentity,
        anchor: GridBoundary,
        sourceRange: Range<Int>,
        displayID: UInt32,
        viewport: GridSelectionViewport?,
        bindingOrigin: SelectionBindingOrigin
    ) -> GridSelectionBindingResult {
        guard let display = activationContext.displays.first(where: {
            $0.displayID == displayID
        }) else {
            return .rejected(.displayUnavailable)
        }
        if let viewport {
            guard viewport.isUsable,
                  viewport.displayID == displayID,
                  anchor.row < viewport.visualRowCount,
                  let maximumColumn = viewport.maximumColumn(within: display.appKitFrame),
                  anchor.column <= maximumColumn
            else {
                return .rejected(.invalidViewport)
            }
        }
        let context = BoundSelectionContext(
            activation: activationContext.activation,
            sessionIdentity: activationContext.sessionIdentity,
            source: source,
            sourceWindowFrame: activationContext.sourceWindowFrame,
            element: element,
            anchor: anchor,
            sourceRange: sourceRange,
            display: display,
            viewport: viewport,
            bindingOrigin: bindingOrigin
        )
        boundContext = context
        return .bound(context)
    }
}
