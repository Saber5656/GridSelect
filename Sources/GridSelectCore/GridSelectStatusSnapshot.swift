public enum ShortcutReadiness: Equatable, Sendable {
    case active(displayName: String)
    case inactive(displayName: String)
    case registrationFailed(displayName: String)

    public var displayName: String {
        switch self {
        case let .active(displayName),
             let .inactive(displayName),
             let .registrationFailed(displayName):
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
    public let permissionStatus: SelectionPermissionStatus
    public let shortcutStatus: ShortcutReadiness
    public let selectionState: SelectionModeState

    public init(
        permissionStatus: SelectionPermissionStatus,
        shortcutStatus: ShortcutReadiness,
        selectionState: SelectionModeState
    ) {
        self.permissionStatus = permissionStatus
        self.shortcutStatus = shortcutStatus
        self.selectionState = selectionState
    }

    public var isReady: Bool {
        permissionStatus == .granted
            && shortcutStatus.isActive
            && !selectionState.isActive
            && selectionState != .permissionRequired
    }

    public var statusTitle: String {
        switch selectionState {
        case .selecting, .dragging, .confirmed, .extracting, .copying:
            return "Selection in progress"
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

        switch shortcutStatus {
        case .active:
            return "Ready to select"
        case .inactive:
            return "Shortcut not active"
        case .registrationFailed:
            return "Shortcut unavailable"
        }
    }

    public var statusDetail: String {
        switch selectionState {
        case .completed:
            return "The rectangular text selection was copied successfully."
        case .cancelled:
            return "Nothing was copied."
        case .permissionRequired:
            return Self.accessibilityGuidance
        case let .failed(failure):
            return failure.statusDetail
        case .selecting, .dragging, .confirmed, .extracting, .copying:
            return "Finish the selection or press Escape to cancel."
        case .idle:
            break
        }

        if permissionStatus == .required {
            return Self.accessibilityGuidance
        }

        switch shortcutStatus {
        case .active:
            return "Press \(shortcutStatus.displayName) to start a rectangular selection."
        case .inactive:
            return "The shortcut \(shortcutStatus.displayName) is currently inactive."
        case .registrationFailed:
            return "GridSelect could not register \(shortcutStatus.displayName). Shortcut configuration is not available in this pre-alpha build."
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
            permissionStatus: updatedPermissionStatus,
            shortcutStatus: shortcutStatus ?? self.shortcutStatus,
            selectionState: updatedSelectionState
        )
    }

    public static let accessibilityGuidance =
        "Open System Settings, then go to Privacy & Security > Accessibility and enable GridSelect."
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
        }
    }
}
