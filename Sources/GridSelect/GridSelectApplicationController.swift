import AppKit
import GridSelectCore

@MainActor
final class MacOSSelectionPermissionChecker: SelectionPermissionChecking {
    var selectionPermissionStatus: SelectionPermissionStatus {
        AccessibilityPermissionClient.status
    }
}

@MainActor
final class GridSelectApplicationController {
    let statusModel: GridSelectStatusModel

    private let coordinator: SelectionModeCoordinator

    init(
        statusModel: GridSelectStatusModel? = nil,
        shortcut: (any SelectionShortcutRegistering)? = nil,
        permissionChecker: (any SelectionPermissionChecking)? = nil,
        overlay: (any SelectionOverlayPresenting)? = nil,
        extractor: (any RectangularTextExtracting)? = nil,
        clipboard: (any ClipboardWriting)? = nil
    ) {
        let permissionChecker = permissionChecker ?? MacOSSelectionPermissionChecker()
        let statusModel = statusModel ?? GridSelectStatusModel(
            permissionStatus: permissionChecker.selectionPermissionStatus,
            permissionStatusProvider: {
                permissionChecker.selectionPermissionStatus
            }
        )
        self.statusModel = statusModel
        coordinator = SelectionModeCoordinator(
            shortcut: shortcut ?? MacOSGlobalShortcut(),
            permissionChecker: permissionChecker,
            overlay: overlay ?? MacOSSelectionOverlay(),
            extractor: extractor ?? MacOSAccessibilityTextExtractor(),
            clipboard: clipboard ?? MacOSPasteboardWriter(),
            stateObserver: { [weak statusModel] state in
                if state == .permissionRequired {
                    statusModel?.recheckPermission()
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
        coordinator.shutdown()
        statusModel.updateShortcutStatus(
            .inactive(displayName: MacOSGlobalShortcut.displayName)
        )
    }

    @discardableResult
    func activateSelection() -> Bool {
        coordinator.activate()
    }

    @discardableResult
    func cancelSelection() -> Bool {
        coordinator.cancel()
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
