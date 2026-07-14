@testable import GridSelect
import ApplicationServices
import Foundation
import GridSelectCore
import XCTest

final class MacOSAccessibilityExtractionEngineTests: XCTestCase {
    func testSecureHitTargetStopsBeforeAncestorTextCalls() {
        let client = FakeAccessibilityClient()
        let secure = client.addElement("secure", pid: 10, role: "AXSecureTextField")
        let parent = client.addElement("parent", pid: 10)
        client.setParent(parent, for: secure)
        client.configureMonospace(parent, lines: ["secret"])
        client.hitTested = secure

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .secureTextElement)
        }
        XCTAssertEqual(client.textReadCount, 0)
        XCTAssertEqual(client.boundsReadCount, 0)
    }

    func testSecureAncestorStopsBeforeReadableChildTextCalls() {
        let client = FakeAccessibilityClient()
        let child = client.addElement("child", pid: 10)
        let secureParent = client.addElement("secure-parent", pid: 10, role: "AXSecureTextField")
        client.setParent(secureParent, for: child)
        client.configureMonospace(child, lines: ["secret"])
        client.hitTested = child

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .secureTextElement)
        }
        XCTAssertEqual(client.textReadCount, 0)
        XCTAssertEqual(client.boundsReadCount, 0)
    }

    func testHitTestedTargetWinsOverFocusedElementFromDifferentPID() throws {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        let focused = client.addElement(
            "focused",
            pid: 20,
            frame: CGRect(x: 80, y: 40, width: 300, height: 200)
        )
        client.configureMonospace(hit, lines: ["hit text"])
        client.configureMonospace(focused, lines: ["wrong app"])
        client.hitTested = hit
        client.focused = focused

        let output = try engine(client).extract(rectangle: selection, display: display)

        XCTAssertEqual(output, "hit ")
        XCTAssertEqual(client.textReadsByElement["focused", default: 0], 0)
    }

    func testFocusedFallbackRequiresFrameContainmentWhenHitTestIsUnavailable() {
        let client = FakeAccessibilityClient()
        let focused = client.addElement(
            "focused",
            pid: 10,
            frame: CGRect(x: 700, y: 700, width: 100, height: 100)
        )
        client.configureMonospace(focused, lines: ["outside"])
        client.focused = focused

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .targetMismatch)
        }
        XCTAssertEqual(client.textReadCount, 0)
    }

    func testEmptyLeafContinuesToSupportedAncestor() throws {
        let client = FakeAccessibilityClient()
        let leaf = client.addElement("leaf", pid: 10)
        let parent = client.addElement("parent", pid: 10)
        client.setParent(parent, for: leaf)
        client.configureMonospace(leaf, lines: ["offscreen"], originX: 500)
        client.configureMonospace(parent, lines: ["ancestor"])
        client.hitTested = leaf

        let output = try engine(client).extract(rectangle: selection, display: display)

        XCTAssertEqual(output, "ance")
        XCTAssertGreaterThan(client.textReadsByElement["parent", default: 0], 0)
    }

    func testMultipleGlyphSamplesRejectProportionalText() {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(
            hit,
            lines: ["iWi"],
            characterWidths: ["i": 4, "W": 12]
        )
        client.hitTested = hit

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .unstableGeometry)
        }
    }

    func testHugeLineNumbersAreRejectedBeforeEnumeration() {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(hit, lines: ["abc"])
        client.forcedLineNumbers = (first: 0, last: Int.max)
        client.hitTested = hit

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .resourceLimitExceeded)
        }
    }

    func testOverflowingAXRangeIsRejected() {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(hit, lines: ["abc"])
        client.elements["hit"]?.visibleRange = CFRange(location: Int.max - 1, length: 10)
        client.hitTested = hit

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .resourceLimitExceeded)
        }
    }

    func testCallBudgetStopsPathologicalTargets() {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(hit, lines: ["abc"])
        client.hitTested = hit
        let limits = AccessibilityExtractionLimits(maximumAXCalls: 3)

        XCTAssertThrowsError(
            try MacOSAccessibilityExtractionEngine(client: client, limits: limits)
                .extract(rectangle: selection, display: display)
        ) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .resourceLimitExceeded)
        }
    }

    func testOverlongAXStringResponseIsRejected() {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(hit, lines: ["abc"])
        client.forcedString = String(repeating: "x", count: 100)
        client.hitTested = hit

        XCTAssertThrowsError(try engine(client).extract(rectangle: selection, display: display)) {
            XCTAssertEqual($0 as? MacOSAccessibilityExtractionError, .resourceLimitExceeded)
        }
        XCTAssertEqual(client.boundsReadCount, 0)
    }

    func testCallerCancellationStopsDetachedExtractionBeforeTextRead() async {
        let client = FakeAccessibilityClient()
        let hit = client.addElement("hit", pid: 10)
        client.configureMonospace(hit, lines: ["abc"])
        client.hitTested = hit
        let enteredPreTextCall = DispatchSemaphore(value: 0)
        let releasePreTextCall = DispatchSemaphore(value: 0)
        client.parameterizedNamesBarrier = (enteredPreTextCall, releasePreTextCall)
        let extractor = MacOSAccessibilityTextExtractor(client: client)
        let selectedRectangle = selection
        let displayGeometry = display

        let extraction = Task {
            try await extractor.extractText(in: selectedRectangle, display: displayGeometry)
        }
        XCTAssertEqual(enteredPreTextCall.wait(timeout: .now() + 2), .success)
        extraction.cancel()
        releasePreTextCall.signal()

        do {
            _ = try await extraction.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        XCTAssertEqual(client.textReadCount, 0)
    }

    private func engine(_ client: FakeAccessibilityClient) -> MacOSAccessibilityExtractionEngine {
        MacOSAccessibilityExtractionEngine(client: client)
    }

    private var display: DisplayGeometry {
        DisplayGeometry(
            displayID: 1,
            appKitFrame: ScreenRectangle(x: 0, y: 0, width: 1_000, height: 1_000),
            coreGraphicsBounds: ScreenRectangle(x: 0, y: 0, width: 1_000, height: 1_000),
            backingScale: 2
        )
    }

    private var selection: SelectionRectangle {
        SelectionRectangle(displayID: 1, x: 100, y: 930, width: 40, height: 20)
    }
}

private final class FakeAccessibilityClient: MacOSAccessibilityClient, @unchecked Sendable {
    struct ElementData {
        var pid: pid_t
        var frame: CGRect?
        var role: String?
        var subrole: String?
        var parentID: String?
        var parameterizedNames: [String] = []
        var visibleRange: CFRange?
        var numberOfCharacters: Int?
        var lines: [LineData] = []
        var characterWidths: [UInt16: Double] = [:]
    }

    struct LineData {
        let range: CFRange
        let rawText: String
        let bounds: CGRect
    }

    var isTrusted = true
    var hitTested: AccessibilityElementHandle?
    var focused: AccessibilityElementHandle?
    var elements: [String: ElementData] = [:]
    var forcedLineNumbers: (first: Int, last: Int)?
    var forcedString: String?
    var parameterizedNamesBarrier: (entered: DispatchSemaphore, release: DispatchSemaphore)?
    private(set) var textReadCount = 0
    private(set) var boundsReadCount = 0
    private(set) var textReadsByElement: [String: Int] = [:]

    func addElement(
        _ id: String,
        pid: pid_t,
        frame: CGRect? = CGRect(x: 80, y: 40, width: 300, height: 200),
        role: String? = "AXTextArea",
        subrole: String? = nil
    ) -> AccessibilityElementHandle {
        elements[id] = ElementData(pid: pid, frame: frame, role: role, subrole: subrole)
        return AccessibilityElementHandle(testIdentifier: id)
    }

    func setParent(_ parent: AccessibilityElementHandle, for child: AccessibilityElementHandle) {
        elements[id(child)]?.parentID = id(parent)
    }

    func configureMonospace(
        _ element: AccessibilityElementHandle,
        lines: [String],
        originX: Double = 100,
        originY: Double = 50,
        characterWidth: Double = 10,
        lineHeight: Double = 20,
        characterWidths: [Character: Double] = [:]
    ) {
        let identifier = id(element)
        var data = elements[identifier]!
        data.parameterizedNames = [
            kAXStringForRangeParameterizedAttribute,
            kAXBoundsForRangeParameterizedAttribute,
            kAXLineForIndexParameterizedAttribute,
            kAXRangeForLineParameterizedAttribute,
        ]
        var location = 0
        data.lines = lines.enumerated().map { index, text in
            let hasTerminator = index < lines.count - 1
            let rawText = text + (hasTerminator ? "\n" : "")
            let range = CFRange(location: location, length: rawText.utf16.count)
            location += rawText.utf16.count
            return LineData(
                range: range,
                rawText: rawText,
                bounds: CGRect(
                    x: originX,
                    y: originY + (Double(index) * lineHeight),
                    width: Double(text.utf16.count) * characterWidth,
                    height: lineHeight
                )
            )
        }
        data.visibleRange = CFRange(location: 0, length: location)
        data.numberOfCharacters = location
        data.characterWidths = Dictionary(
            uniqueKeysWithValues: characterWidths.compactMap { character, width in
                guard let codeUnit = character.utf16.first else {
                    return nil
                }
                return (codeUnit, width)
            }
        )
        if data.characterWidths.isEmpty {
            let allCodeUnits = lines.joined().utf16
            data.characterWidths = Dictionary(
                uniqueKeysWithValues: Set(allCodeUnits).map { ($0, characterWidth) }
            )
        }
        elements[identifier] = data
    }

    func hitTestedElement(at point: CGPoint) -> AccessibilityElementHandle? { hitTested }
    func focusedElement() -> AccessibilityElementHandle? { focused }

    func parent(of element: AccessibilityElementHandle) -> AccessibilityElementHandle? {
        guard let parentID = elements[id(element)]?.parentID else {
            return nil
        }
        return AccessibilityElementHandle(testIdentifier: parentID)
    }

    func isSameElement(
        _ lhs: AccessibilityElementHandle,
        _ rhs: AccessibilityElementHandle
    ) -> Bool {
        id(lhs) == id(rhs)
    }

    func pid(of element: AccessibilityElementHandle) -> pid_t? { elements[id(element)]?.pid }
    func frame(of element: AccessibilityElementHandle) -> CGRect? { elements[id(element)]?.frame }
    func role(of element: AccessibilityElementHandle) -> String? { elements[id(element)]?.role }
    func subrole(of element: AccessibilityElementHandle) -> String? { elements[id(element)]?.subrole }
    func setMessagingTimeout(_ seconds: Float, for element: AccessibilityElementHandle) {}

    func parameterizedAttributeNames(of element: AccessibilityElementHandle) -> [String] {
        if let barrier = parameterizedNamesBarrier {
            barrier.entered.signal()
            _ = barrier.release.wait(timeout: .now() + 2)
        }
        return elements[id(element)]?.parameterizedNames ?? []
    }

    func visibleCharacterRange(of element: AccessibilityElementHandle) -> CFRange? {
        elements[id(element)]?.visibleRange
    }

    func numberOfCharacters(in element: AccessibilityElementHandle) -> Int? {
        elements[id(element)]?.numberOfCharacters
    }

    func line(for index: Int, in element: AccessibilityElementHandle) -> Int? {
        if let forcedLineNumbers {
            return index == elements[id(element)]?.visibleRange?.location
                ? forcedLineNumbers.first
                : forcedLineNumbers.last
        }
        return elements[id(element)]?.lines.firstIndex(where: {
            index >= $0.range.location && index < $0.range.location + $0.range.length
        })
    }

    func range(forLine line: Int, in element: AccessibilityElementHandle) -> CFRange? {
        guard let lines = elements[id(element)]?.lines, lines.indices.contains(line) else {
            return nil
        }
        return lines[line].range
    }

    func string(for range: CFRange, in element: AccessibilityElementHandle) -> String? {
        let identifier = id(element)
        textReadCount += 1
        textReadsByElement[identifier, default: 0] += 1
        return forcedString ?? elements[identifier]?.lines.first(where: {
            $0.range.location == range.location && $0.range.length == range.length
        })?.rawText
    }

    func bounds(for range: CFRange, in element: AccessibilityElementHandle) -> CGRect? {
        boundsReadCount += 1
        guard let data = elements[id(element)],
              let line = data.lines.first(where: {
                  range.location >= $0.range.location
                      && range.location + range.length <= $0.range.location + $0.range.length
              })
        else {
            return nil
        }
        if range.length == 1 {
            let offset = range.location - line.range.location
            let codeUnits = Array(line.rawText.utf16)
            guard codeUnits.indices.contains(offset) else {
                return nil
            }
            let width = data.characterWidths[codeUnits[offset]] ?? 10
            return CGRect(x: line.bounds.minX, y: line.bounds.minY, width: width, height: line.bounds.height)
        }
        return line.bounds
    }

    private func id(_ element: AccessibilityElementHandle) -> String {
        element.testIdentifier!
    }
}
