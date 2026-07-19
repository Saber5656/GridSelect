@testable import GridSelect
import CoreGraphics
import XCTest

@MainActor
final class MacOSActivationSourceCapturerTests: XCTestCase {
    func testFocusedDocumentWinsOverFrontmostHelperWindow() {
        let helper = window(id: 16_045, x: 188, y: 89, width: 66, height: 20)
        let document = window(id: 16_037, x: 182, y: 83, width: 656, height: 422)

        XCTAssertEqual(
            MacOSActivationSourceCapturer.preferredWindow(
                candidates: [helper, document],
                focusedWindowResolution: .resolved(document.frame)
            ),
            document
        )
    }

    func testFocusedSmallWindowIsNotFilteredBySize() {
        let smallWindow = window(id: 7, x: 30, y: 40, width: 66, height: 20)
        let largerWindow = window(id: 8, x: 100, y: 120, width: 800, height: 600)

        XCTAssertEqual(
            MacOSActivationSourceCapturer.preferredWindow(
                candidates: [smallWindow, largerWindow],
                focusedWindowResolution: .resolved(smallWindow.frame)
            ),
            smallWindow
        )
    }

    func testUntrustedAccessibilityPreservesPermissionFallbackOrder() {
        let frontmost = window(id: 1, x: 10, y: 20, width: 300, height: 200)
        let second = window(id: 2, x: 40, y: 50, width: 600, height: 400)

        XCTAssertEqual(
            MacOSActivationSourceCapturer.preferredWindow(
                candidates: [frontmost, second],
                focusedWindowResolution: .notTrusted
            ),
            frontmost
        )
    }

    func testTrustedFocusedWindowQueryFailureFailsClosed() {
        let frontmost = window(id: 1, x: 10, y: 20, width: 300, height: 200)
        let second = window(id: 2, x: 40, y: 50, width: 600, height: 400)

        XCTAssertNil(
            MacOSActivationSourceCapturer.preferredWindow(
                candidates: [frontmost, second],
                focusedWindowResolution: .queryFailed
            )
        )
    }

    func testFocusedFrameMustMatchExactlyOneCandidate() {
        let first = window(id: 1, x: 10, y: 20, width: 300, height: 200)
        let duplicate = window(id: 2, x: 10, y: 20, width: 300, height: 200)
        let unrelated = CGRect(x: 500, y: 500, width: 100, height: 100)

        XCTAssertNil(
            MacOSActivationSourceCapturer.preferredWindow(
                candidates: [first, duplicate],
                focusedWindowResolution: .resolved(first.frame)
            )
        )
        XCTAssertNil(
            MacOSActivationSourceCapturer.preferredWindow(
                candidates: [
                    first,
                    window(id: 3, x: 30, y: 40, width: 500, height: 400),
                ],
                focusedWindowResolution: .resolved(unrelated)
            )
        )
    }

    func testFocusedFrameUsesExistingOnePointTolerance() {
        let candidate = window(id: 1, x: 10, y: 20, width: 300, height: 200)
        let withinTolerance = CGRect(x: 11, y: 19, width: 301, height: 199)
        let outsideTolerance = CGRect(x: 11.01, y: 20, width: 300, height: 200)

        XCTAssertEqual(
            MacOSActivationSourceCapturer.preferredWindow(
                candidates: [candidate],
                focusedWindowResolution: .resolved(withinTolerance)
            ),
            candidate
        )
        XCTAssertNil(
            MacOSActivationSourceCapturer.preferredWindow(
                candidates: [candidate],
                focusedWindowResolution: .resolved(outsideTolerance)
            )
        )
    }

    private func window(
        id: UInt32,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> MacOSActivationSourceCapturer.WindowSnapshot {
        MacOSActivationSourceCapturer.WindowSnapshot(
            identifier: id,
            frame: CGRect(x: x, y: y, width: width, height: height)
        )
    }
}
