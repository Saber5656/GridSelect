import AppKit
@testable import GridSelect
import GridSelectCore
import XCTest

@MainActor
final class MacOSSelectionOverlayTests: XCTestCase {
    func testShiftReleaseRecognitionIgnoresOtherModifierChanges() {
        XCTAssertTrue(
            MacOSSelectionOverlay.isShiftRelease(keyCode: 56, modifierFlags: [])
        )
        XCTAssertTrue(
            MacOSSelectionOverlay.isShiftRelease(keyCode: 60, modifierFlags: [])
        )
        XCTAssertFalse(
            MacOSSelectionOverlay.isShiftRelease(keyCode: 56, modifierFlags: .shift)
        )
        for keyCode: UInt16 in [55, 57, 58, 59, 63] {
            XCTAssertFalse(
                MacOSSelectionOverlay.isShiftRelease(
                    keyCode: keyCode,
                    modifierFlags: []
                )
            )
        }
    }

    func testGridInteractionRequiresKeyboardBindingOrMouseResolver() {
        let valid = sourceContext(viewport: viewport())
        XCTAssertNotNil(
            MacOSSelectionOverlay.makeGridInteraction(
                sourceContext: valid,
                hasMouseAnchorResolver: false
            )
        )

        let invalid = sourceContext(viewport: nil)
        XCTAssertNil(
            MacOSSelectionOverlay.makeGridInteraction(
                sourceContext: invalid,
                hasMouseAnchorResolver: false
            )
        )
        XCTAssertNotNil(
            MacOSSelectionOverlay.makeGridInteraction(
                sourceContext: invalid,
                hasMouseAnchorResolver: true
            )
        )
    }

    private func sourceContext(
        viewport: GridSelectionViewport?
    ) -> ActivationSourceContext {
        ActivationSourceContext(
            activation: GridActivation(generation: 1),
            source: SelectionSourceIdentity(processIdentifier: 42, windowIdentifier: 7),
            sourceWindowFrame: ScreenRectangle(x: 0, y: 0, width: 500, height: 500),
            displays: [
                DisplayGeometry(
                    displayID: 1,
                    appKitFrame: ScreenRectangle(x: 0, y: 0, width: 500, height: 500),
                    coreGraphicsBounds: ScreenRectangle(x: 0, y: 0, width: 500, height: 500),
                    backingScale: 2
                ),
            ],
            caretCandidate: GridCaretCandidate(
                element: SelectionElementIdentity(rawValue: 3),
                anchor: GridBoundary(row: 1, column: 2),
                sourceRange: 4..<4,
                displayID: 1,
                viewport: viewport
            )
        )
    }

    private func viewport() -> GridSelectionViewport {
        GridSelectionViewport(
            displayID: 1,
            originX: 100,
            topY: 500,
            characterWidth: 10,
            lineHeight: 20,
            visualRowCount: 5
        )
    }
}
