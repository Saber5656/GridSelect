import AppKit
import GridSelectCore

enum MacOSPasteboardWriteError: Error, Equatable, LocalizedError {
    case rejected

    var errorDescription: String? {
        "macOS rejected the plain-text clipboard write."
    }
}

@MainActor
protocol MacOSPasteboardAccess: AnyObject {
    func replacePlainText(with value: String) -> Bool
}

@MainActor
final class SystemMacOSPasteboardAccess: MacOSPasteboardAccess {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func replacePlainText(with value: String) -> Bool {
        let item = NSPasteboardItem()
        guard item.setString(value, forType: .string) else {
            return false
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}

@MainActor
final class MacOSPasteboardWriter: ClipboardWriting {
    private let pasteboard: any MacOSPasteboardAccess

    init(pasteboard: any MacOSPasteboardAccess = SystemMacOSPasteboardAccess()) {
        self.pasteboard = pasteboard
    }

    func writePlainText(_ text: String) throws {
        guard !text.isEmpty else {
            return
        }

        guard pasteboard.replacePlainText(with: text) else {
            throw MacOSPasteboardWriteError.rejected
        }
    }
}
