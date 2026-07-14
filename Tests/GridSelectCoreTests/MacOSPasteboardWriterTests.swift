@testable import GridSelect
import AppKit
import XCTest

@MainActor
final class MacOSPasteboardWriterTests: XCTestCase {
    func testWritesOnlyPlainTextAfterClearingPasteboard() throws {
        let access = PasteboardAccessStub()
        let writer = MacOSPasteboardWriter(pasteboard: access)

        try writer.writePlainText("alpha  \nbravo  ")

        XCTAssertEqual(access.writes.count, 1)
        XCTAssertEqual(access.writes.first, "alpha  \nbravo  ")
    }

    func testSystemAccessReplacesNamedPasteboardWithOnePlainTextItem() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("previous clipboard", forType: .string)
        let writer = MacOSPasteboardWriter(
            pasteboard: SystemMacOSPasteboardAccess(pasteboard: pasteboard)
        )

        try writer.writePlainText("selected")

        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertEqual(pasteboard.pasteboardItems?.first?.types, [.string])
        XCTAssertEqual(pasteboard.pasteboardItems?.first?.string(forType: .string), "selected")
    }

    func testRejectedWriteThrowsTypedError() {
        let access = PasteboardAccessStub()
        access.acceptWrite = false
        let writer = MacOSPasteboardWriter(pasteboard: access)

        XCTAssertThrowsError(try writer.writePlainText("selected")) {
            XCTAssertEqual($0 as? MacOSPasteboardWriteError, .rejected)
        }
        XCTAssertTrue(access.writes.isEmpty)
    }

    func testEmptyTextDoesNotMutatePasteboard() throws {
        let access = PasteboardAccessStub()

        try MacOSPasteboardWriter(pasteboard: access).writePlainText("")

        XCTAssertTrue(access.writes.isEmpty)
    }
}

@MainActor
private final class PasteboardAccessStub: MacOSPasteboardAccess {
    var acceptWrite = true
    private(set) var writes: [String] = []

    func replacePlainText(with value: String) -> Bool {
        guard acceptWrite else {
            return false
        }
        writes.append(value)
        return true
    }
}
