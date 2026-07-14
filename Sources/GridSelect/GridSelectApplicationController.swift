import AppKit
import GridSelectCore

@MainActor
final class MacOSSelectionPermissionChecker: SelectionPermissionChecking {
    var selectionPermissionStatus: SelectionPermissionStatus {
        AccessibilityPermissionClient.status
    }
}

@MainActor
protocol PermissionSetupPresenting: AnyObject {
    func presentPermissionSetup()
}

@MainActor
final class MacOSPermissionSetupPresenter: PermissionSetupPresenting {
    func presentPermissionSetup() {
        NSApplication.shared.sendAction(
            Selector(("showSettingsWindow:")),
            to: nil,
            from: nil
        )
        NSApplication.shared.requestUserAttention(.informationalRequest)
    }
}

@MainActor
final class GridSelectApplicationController {
    let statusModel: GridSelectStatusModel

    private let coordinator: SelectionModeCoordinator
    private let accessibilityService: MacOSAccessibilitySelectionService
    private var manualActivationGeneration: UInt64 = 0
    private var manualCaptureTask: Task<Void, Never>?
    private var manualCaptureSessionIdentity: SelectionSessionIdentity?

    init(
        statusModel: GridSelectStatusModel? = nil,
        shortcut: (any SelectionShortcutRegistering)? = nil,
        permissionChecker: (any SelectionPermissionChecking)? = nil,
        permissionSetupPresenter: (any PermissionSetupPresenting)? = nil,
        overlay: (any SelectionOverlayPresenting)? = nil,
        extractor: (any RectangularTextExtracting)? = nil,
        clipboard: (any ClipboardWriting)? = nil
    ) {
        let permissionChecker = permissionChecker ?? MacOSSelectionPermissionChecker()
        let permissionSetupPresenter = permissionSetupPresenter ?? MacOSPermissionSetupPresenter()
        let statusModel = statusModel ?? GridSelectStatusModel(
            permissionStatus: permissionChecker.selectionPermissionStatus,
            permissionStatusProvider: {
                permissionChecker.selectionPermissionStatus
            }
        )
        let accessibilityService = MacOSAccessibilitySelectionService()
        self.accessibilityService = accessibilityService
        self.statusModel = statusModel
        coordinator = SelectionModeCoordinator(
            shortcut: shortcut ?? MacOSGlobalShortcut(
                accessibilityService: accessibilityService
            ),
            permissionChecker: permissionChecker,
            overlay: overlay ?? MacOSSelectionOverlay(
                mouseAnchorResolver: accessibilityService
            ),
            extractor: extractor ?? accessibilityService,
            clipboard: clipboard ?? MacOSPasteboardWriter(),
            stateObserver: { [weak statusModel] state in
                if state == .permissionRequired {
                    statusModel?.recheckPermission()
                    permissionSetupPresenter.presentPermissionSetup()
                }
                statusModel?.updateSelectionState(state)
            }
        )
    }

    @discardableResult
    func start() -> Bool {
        statusModel.recheckPermission()
        let installed = coordinator.installShortcut()
        statusModel.updateShortcutStatus(
            installed
                ? .active(displayName: MacOSGlobalShortcut.displayName)
                : .registrationFailed(displayName: MacOSGlobalShortcut.displayName)
        )
        return installed
    }

    func stop() {
        manualCaptureTask?.cancel()
        manualCaptureTask = nil
        manualCaptureSessionIdentity = nil
        coordinator.shutdown()
        statusModel.updateShortcutStatus(
            .inactive(displayName: MacOSGlobalShortcut.displayName)
        )
    }

    @discardableResult
    func activateSelection() -> Bool {
        guard manualActivationGeneration < UInt64.max else {
            return false
        }
        manualActivationGeneration += 1
        guard let sourceContext = MacOSActivationSourceCapturer.capture(
            activation: GridActivation(generation: manualActivationGeneration),
            accessibilityService: nil
        ) else {
            coordinator.reportSourceFailure(.sourceContextInvalid)
            return false
        }
        return beginManualCapture(
            sourceContext: sourceContext,
            capture: { [accessibilityService] in
            let captureTask = Task.detached(priority: .userInitiated) {
                accessibilityService.captureCaretCandidate(
                    activation: sourceContext.activation,
                    sessionIdentity: sourceContext.sessionIdentity!,
                    source: sourceContext.source,
                    sourceWindowFrame: sourceContext.sourceWindowFrame,
                    displays: sourceContext.displays
                )
            }
            return await withTaskCancellationHandler {
                await captureTask.value
            } onCancel: {
                captureTask.cancel()
            }
            }
        )
    }

    @discardableResult
    func beginManualCapture(
        sourceContext: ActivationSourceContext,
        capture: @escaping @Sendable () async -> MacOSCaretCaptureResult
    ) -> Bool {
        guard sourceContext.sessionIdentity != nil else {
            coordinator.reportSourceFailure(.sourceContextInvalid)
            return false
        }
        manualCaptureTask?.cancel()
        manualCaptureSessionIdentity = sourceContext.sessionIdentity
        manualCaptureTask = Task { @MainActor [weak self] in
            guard let self, let sessionIdentity = sourceContext.sessionIdentity else {
                return
            }
            var delivered = false
            defer {
                if self.manualCaptureSessionIdentity == sessionIdentity {
                    self.manualCaptureTask = nil
                    self.manualCaptureSessionIdentity = nil
                }
                if !delivered {
                    self.accessibilityService.discardBoundContextsSynchronously(
                        for: sessionIdentity
                    )
                }
            }
            let result = await capture()
            guard !Task.isCancelled else {
                return
            }
            switch result {
            case let .captured(candidate):
                delivered = true
                _ = self.handleManualCaptureResult(
                    .captured(candidate),
                    sourceContext: sourceContext
                )
            case .unavailable:
                delivered = true
                _ = self.handleManualCaptureResult(
                    .unavailable,
                    sourceContext: sourceContext
                )
            case let .rejected(failure):
                _ = self.handleManualCaptureResult(
                    .rejected(failure),
                    sourceContext: sourceContext
                )
            }
        }
        return true
    }

    @discardableResult
    func handleManualCaptureResult(
        _ result: MacOSCaretCaptureResult,
        sourceContext: ActivationSourceContext
    ) -> Bool {
        switch result {
        case let .captured(candidate):
            return coordinator.activate(
                sourceContext: ActivationSourceContext(
                    activation: sourceContext.activation,
                    sessionIdentity: sourceContext.sessionIdentity,
                    source: sourceContext.source,
                    sourceWindowFrame: sourceContext.sourceWindowFrame,
                    displays: sourceContext.displays,
                    caretCandidate: candidate
                )
            )
        case .unavailable:
            return coordinator.activate(sourceContext: sourceContext)
        case let .rejected(failure):
            coordinator.reportSourceFailure(failure)
            return false
        }
    }

    @discardableResult
    func cancelSelection() -> Bool {
        if let manualCaptureTask {
            manualCaptureTask.cancel()
            self.manualCaptureTask = nil
            manualCaptureSessionIdentity = nil
            return true
        }
        return coordinator.cancel()
    }

}

@MainActor
final class GridSelectAppDelegate: NSObject, NSApplicationDelegate {
    let controller = GridSelectApplicationController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        controller.statusModel.recheckPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}
