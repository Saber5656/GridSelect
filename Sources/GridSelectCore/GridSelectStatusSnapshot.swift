public enum ShortcutReadiness: Equatable, Sendable {
    case active(displayName: String)
    case inactive(displayName: String)
    case registrationFailed(displayName: String)
    case inputMonitoringRequired(displayName: String)

    public var displayName: String {
        switch self {
        case let .active(displayName),
             let .inactive(displayName),
             let .registrationFailed(displayName),
             let .inputMonitoringRequired(displayName):
            return displayName
        }
    }

    public var isActive: Bool {
        if case .active = self {
            return true
        }
        return false
    }
}

public struct GridSelectStatusSnapshot: Equatable, Sendable {
    public let inputMonitoringStatus: SelectionPermissionStatus
    public let permissionStatus: SelectionPermissionStatus
    public let shortcutStatus: ShortcutReadiness
    public let selectionState: SelectionModeState

    public init(
        inputMonitoringStatus: SelectionPermissionStatus,
        permissionStatus: SelectionPermissionStatus,
        shortcutStatus: ShortcutReadiness,
        selectionState: SelectionModeState
    ) {
        self.inputMonitoringStatus = inputMonitoringStatus
        self.permissionStatus = permissionStatus
        self.shortcutStatus = shortcutStatus
        self.selectionState = selectionState
    }

    public var isReady: Bool {
        inputMonitoringStatus == .granted
            && permissionStatus == .granted
            && shortcutStatus.isActive
            && !selectionState.isActive
            && selectionState != .permissionRequired
    }

    public var statusTitle: String {
        if (inputMonitoringStatus == .required
            || shortcutStatus.requiresInputMonitoring),
           (
               selectionState == .failed(.shortcutRegistrationFailed)
                   || selectionState == .failed(.listenerDisabled)
           ) {
            return "Input Monitoring required"
        }
        switch selectionState {
        case .selecting:
            return "Grid mode armed"
        case .dragging:
            return "Adjusting selection"
        case .confirmed:
            return "Selection frozen"
        case .extracting:
            return "Reading selection"
        case .copying:
            return "Copying selection"
        case .completed:
            return "Copied to clipboard"
        case .cancelled:
            return "Selection cancelled"
        case .permissionRequired:
            return "Accessibility required"
        case let .failed(failure):
            return failure.statusTitle
        case .idle:
            break
        }

        if permissionStatus == .required {
            return "Accessibility required"
        }
        if inputMonitoringStatus == .required {
            return "Input Monitoring required"
        }

        switch shortcutStatus {
        case .active:
            return "Ready to select"
        case .inactive:
            return "Shortcut not active"
        case .registrationFailed:
            return "Shortcut unavailable"
        case .inputMonitoringRequired:
            return "Input Monitoring required"
        }
    }

    public var statusDetail: String {
        if (inputMonitoringStatus == .required
            || shortcutStatus.requiresInputMonitoring),
           (
               selectionState == .failed(.shortcutRegistrationFailed)
                   || selectionState == .failed(.listenerDisabled)
           ) {
            return Self.inputMonitoringGuidance
        }
        switch selectionState {
        case .completed:
            return "The rectangular text selection was copied successfully."
        case .cancelled:
            return "Nothing was copied."
        case .permissionRequired:
            return Self.accessibilityGuidance
        case let .failed(failure):
            return failure.statusDetail
        case .selecting:
            return "The caret is the zero-area start. Hold Shift and use Arrow keys, or click and drag supported monospace text."
        case .dragging:
            return "Adjust the character-cell rectangle, then release Shift or the mouse to freeze it."
        case .confirmed:
            return "Press Command-C to copy the nonzero-width rectangle, or Escape to cancel."
        case .extracting:
            return "GridSelect is reading the exact bound text source. Press Escape to cancel."
        case .copying:
            return "GridSelect is validating the source and writing rectangular plain text. Press Escape to cancel."
        case .idle:
            break
        }

        if permissionStatus == .required {
            return Self.accessibilityGuidance
        }
        if inputMonitoringStatus == .required {
            return Self.inputMonitoringGuidance
        }

        switch shortcutStatus {
        case .active:
            return "Press \(shortcutStatus.displayName) to start a rectangular selection."
        case .inactive:
            return "The shortcut \(shortcutStatus.displayName) is currently inactive."
        case .registrationFailed:
            return "GridSelect could not register \(shortcutStatus.displayName). Shortcut configuration is not available in this pre-alpha build."
        case .inputMonitoringRequired:
            return Self.inputMonitoringGuidance
        }
    }

    public var statusSymbolName: String {
        switch selectionState {
        case .completed:
            return "checkmark.circle.fill"
        case .selecting, .dragging, .confirmed, .extracting, .copying:
            return "hourglass.circle"
        case .cancelled:
            return "minus.circle"
        case .permissionRequired, .failed:
            return "exclamationmark.triangle.fill"
        case .idle:
            return isReady
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill"
        }
    }

    public func updating(
        inputMonitoringStatus: SelectionPermissionStatus? = nil,
        permissionStatus: SelectionPermissionStatus? = nil,
        shortcutStatus: ShortcutReadiness? = nil,
        selectionState: SelectionModeState? = nil
    ) -> Self {
        let updatedPermissionStatus = permissionStatus ?? self.permissionStatus
        let updatedSelectionState: SelectionModeState
        if permissionStatus == .granted,
           selectionState == nil,
           self.selectionState == .permissionRequired {
            updatedSelectionState = .idle
        } else {
            updatedSelectionState = selectionState ?? self.selectionState
        }

        return Self(
            inputMonitoringStatus: inputMonitoringStatus ?? self.inputMonitoringStatus,
            permissionStatus: updatedPermissionStatus,
            shortcutStatus: shortcutStatus ?? self.shortcutStatus,
            selectionState: updatedSelectionState
        )
    }

    public static let accessibilityGuidance =
        "Open System Settings, then go to Privacy & Security > Accessibility and enable GridSelect, then recheck."
    public static let inputMonitoringGuidance =
        "Open System Settings, then go to Privacy & Security > Input Monitoring, enable GridSelect, and use Recheck Permissions to recheck."
}

private extension ShortcutReadiness {
    var requiresInputMonitoring: Bool {
        if case .inputMonitoringRequired = self {
            return true
        }
        return false
    }
}

private extension SelectionModeFailure {
    var statusTitle: String {
        switch self {
        case .shortcutRegistrationFailed:
            return "Shortcut unavailable"
        case .listenerDisabled:
            return "Grid listener disabled"
        case .overlayFailed:
            return "Selection could not start"
        case .extractionFailed:
            return "Text could not be read"
        case .clipboardWriteFailed:
            return "Copy failed"
        case .secureInputUnsupported:
            return "Secure input is unsupported"
        case .sourceContextInvalid:
            return "Source changed"
        case .unsupportedText:
            return "Text region unsupported"
        }
    }

    var statusDetail: String {
        switch self {
        case .shortcutRegistrationFailed:
            return "The shortcut could not be registered in this pre-alpha build."
        case .listenerDisabled:
            return "macOS disabled the Grid input listener. Recheck Input Monitoring before retrying."
        case .overlayFailed:
            return "GridSelect could not show the selection overlay."
        case .extractionFailed:
            return "GridSelect could not extract text from this selection."
        case .clipboardWriteFailed:
            return "GridSelect could not write the selected text to the clipboard."
        case .secureInputUnsupported:
            return "GridSelect does not inspect or copy secure text. Choose a non-secure text region."
        case .sourceContextInvalid:
            return "The source app, window, or focused text changed. Start a new Grid selection."
        case .unsupportedText:
            return "This text region does not expose stable monospace accessibility geometry."
        }
    }
}
