import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import GridSelectCore

enum MacOSAccessibilityExtractionError: Error, Equatable, LocalizedError {
    case displayUnavailable
    case noTextCandidate
    case targetMismatch
    case secureTextElement
    case requiredAttributesUnavailable
    case visibleRangeUnavailable
    case visibleRangeTooLarge(limit: Int)
    case lineGeometryUnavailable
    case unstableGeometry
    case resourceLimitExceeded
    case timedOut
    case unsupportedMapping(GridMappingUnsupportedReason)

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            return "The selected display is no longer available. Start a new selection."
        case .noTextCandidate:
            return "No accessible text element was found under the selection."
        case .targetMismatch:
            return "The accessible text target does not match the selected app."
        case .secureTextElement:
            return "GridSelect does not read secure text fields."
        case .requiredAttributesUnavailable:
            return "This app does not expose the text-range geometry GridSelect needs."
        case .visibleRangeUnavailable:
            return "This app does not expose a bounded visible text range."
        case let .visibleRangeTooLarge(limit):
            return "The accessible text range exceeds the safe limit of \(limit) characters."
        case .lineGeometryUnavailable:
            return "This app does not expose stable visual line geometry."
        case .unstableGeometry:
            return "The selected text is not a stable monospace grid."
        case .resourceLimitExceeded:
            return "The target returned more accessibility data than GridSelect can safely inspect."
        case .timedOut:
            return "The target app did not provide accessibility text in time."
        case let .unsupportedMapping(reason):
            return "The selected text is unsupported: \(reason)."
        }
    }
}

final class AccessibilityElementHandle: @unchecked Sendable {
    fileprivate let rawElement: AXUIElement?
    let testIdentifier: String?

    fileprivate init(rawElement: AXUIElement) {
        self.rawElement = rawElement
        testIdentifier = nil
    }

    init(testIdentifier: String) {
        rawElement = nil
        self.testIdentifier = testIdentifier
    }
}

protocol MacOSAccessibilityClient: Sendable {
    var isTrusted: Bool { get }

    func hitTestedElement(at point: CGPoint, inProcess processIdentifier: pid_t?)
        -> AccessibilityElementHandle?
    func focusedElement(inProcess processIdentifier: pid_t?) -> AccessibilityElementHandle?
    func parent(of element: AccessibilityElementHandle) -> AccessibilityElementHandle?
    func childCount(of element: AccessibilityElementHandle) -> Int?
    func children(
        of element: AccessibilityElementHandle,
        limit: Int
    ) -> [AccessibilityElementHandle]?
    func window(of element: AccessibilityElementHandle) -> AccessibilityElementHandle?
    func windowCount(inProcess processIdentifier: pid_t) -> Int?
    func windows(
        inProcess processIdentifier: pid_t,
        limit: Int
    ) -> [AccessibilityElementHandle]?
    func isSameElement(_ lhs: AccessibilityElementHandle, _ rhs: AccessibilityElementHandle) -> Bool
    func pid(of element: AccessibilityElementHandle) -> pid_t?
    func frame(of element: AccessibilityElementHandle) -> CGRect?
    func role(of element: AccessibilityElementHandle) -> String?
    func subrole(of element: AccessibilityElementHandle) -> String?
    func setMessagingTimeout(_ seconds: Float, for element: AccessibilityElementHandle)
    func parameterizedAttributeNames(of element: AccessibilityElementHandle) -> [String]
    func visibleCharacterRange(of element: AccessibilityElementHandle) -> CFRange?
    func selectedTextRange(of element: AccessibilityElementHandle) -> CFRange?
    func numberOfCharacters(in element: AccessibilityElementHandle) -> Int?
    func line(for index: Int, in element: AccessibilityElementHandle) -> Int?
    func range(forLine line: Int, in element: AccessibilityElementHandle) -> CFRange?
    func string(for range: CFRange, in element: AccessibilityElementHandle) -> String?
    func bounds(for range: CFRange, in element: AccessibilityElementHandle) -> CGRect?
}

struct AccessibilityExtractionLimits: Equatable, Sendable {
    let maximumVisibleCharacters: Int
    let maximumCandidates: Int
    let maximumVisualLines: Int
    let maximumWidthSamplesPerLine: Int
    let maximumAXCalls: Int
    let totalTimeout: TimeInterval
    let perMessageTimeout: Float

    init(
        maximumVisibleCharacters: Int = 20_000,
        maximumCandidates: Int = 10,
        maximumVisualLines: Int = 256,
        maximumWidthSamplesPerLine: Int = 8,
        maximumAXCalls: Int = 2_500,
        totalTimeout: TimeInterval = 5,
        perMessageTimeout: Float = 1
    ) {
        self.maximumVisibleCharacters = max(1, maximumVisibleCharacters)
        self.maximumCandidates = max(1, maximumCandidates)
        self.maximumVisualLines = max(1, maximumVisualLines)
        self.maximumWidthSamplesPerLine = max(1, maximumWidthSamplesPerLine)
        self.maximumAXCalls = max(1, maximumAXCalls)
        self.totalTimeout = max(0.1, totalTimeout)
        self.perMessageTimeout = max(0.1, perMessageTimeout)
    }
}

struct MacOSAccessibilityExtractionEngine: Sendable {
    private let client: any MacOSAccessibilityClient
    private let limits: AccessibilityExtractionLimits

    init(
        client: any MacOSAccessibilityClient,
        limits: AccessibilityExtractionLimits = AccessibilityExtractionLimits()
    ) {
        self.client = client
        self.limits = limits
    }

    func extract(
        rectangle: SelectionRectangle,
        display: DisplayGeometry
    ) throws -> String {
        guard client.isTrusted else {
            throw SelectionPermissionRequiredError()
        }
        guard let canonical = display.canonicalRectangle(for: rectangle) else {
            throw MacOSAccessibilityExtractionError.displayUnavailable
        }

        let budget = ExtractionBudget(limits: limits)
        let center = CGPoint(
            x: canonical.minX + (canonical.width / 2),
            y: canonical.minY + (canonical.height / 2)
        )
        try budget.check()
        let hitTested = client.hitTestedElement(at: center, inProcess: nil)
        try budget.check()
        let focused = client.focusedElement(inProcess: nil)

        var chains: [[AccessibilityElementHandle]] = []
        var targetPID: pid_t?

        if let hitTested {
            let hitTestedPID = try checkedPID(of: hitTested, budget: budget)
            client.setMessagingTimeout(limits.perMessageTimeout, for: hitTested)
            targetPID = hitTestedPID
            chains.append(
                try candidateChain(
                    startingAt: hitTested,
                    requiredPID: hitTestedPID,
                    budget: budget
                )
            )
        }

        if let focused,
           let focusedPID = try authorizedFocusedFallbackPID(
               focused,
               targetPID: targetPID,
               selectionCenter: center,
               budget: budget
           ),
           !chains.joined().contains(where: { client.isSameElement($0, focused) })
        {
            chains.append(
                try candidateChain(
                    startingAt: focused,
                    requiredPID: focusedPID,
                    budget: budget
                )
            )
        }

        guard chains.reduce(0, { $0 + $1.count }) <= limits.maximumCandidates else {
            throw MacOSAccessibilityExtractionError.resourceLimitExceeded
        }

        guard !chains.isEmpty else {
            throw hitTested == nil && focused != nil
                ? MacOSAccessibilityExtractionError.targetMismatch
                : MacOSAccessibilityExtractionError.noTextCandidate
        }

        var sawEmpty = false
        var lastRecoverableError: MacOSAccessibilityExtractionError = .requiredAttributesUnavailable
        for chain in chains {
            for candidate in chain {
                try budget.check()
                do {
                    let snapshot = try snapshot(from: candidate, budget: budget)
                    let mapping = CoordinateGridMapper().map(
                        selection: rectangle,
                        display: display,
                        grid: snapshot.grid,
                        visualLines: snapshot.lines,
                        policy: GridMappingPolicy()
                    )

                    switch mapping {
                    case let .selection(selection):
                        return selection.plainText
                    case .empty:
                        sawEmpty = true
                        continue
                    case let .unsupported(reason):
                        throw MacOSAccessibilityExtractionError.unsupportedMapping(reason)
                    }
                } catch let error as MacOSAccessibilityExtractionError {
                    switch error {
                    case .requiredAttributesUnavailable,
                         .visibleRangeUnavailable,
                         .lineGeometryUnavailable,
                         .unstableGeometry:
                        lastRecoverableError = error
                        continue
                    case .displayUnavailable,
                         .noTextCandidate,
                         .targetMismatch,
                         .secureTextElement,
                         .visibleRangeTooLarge,
                         .resourceLimitExceeded,
                         .timedOut,
                         .unsupportedMapping:
                        throw error
                    }
                }
            }
        }

        if sawEmpty {
            return ""
        }
        throw lastRecoverableError
    }

    struct BoundCandidate: @unchecked Sendable {
        let element: AccessibilityElementHandle
        let grid: TextGridGeometry
        let lines: [VisualLine]

        var sourceRange: Range<Int> {
            let locations = lines.compactMap(\.sourceLocation)
            let ends = lines.compactMap { line -> Int? in
                guard let location = line.sourceLocation,
                      let length = line.sourceLength
                else {
                    return nil
                }
                let (end, overflow) = location.addingReportingOverflow(length)
                return overflow ? nil : end
            }
            return (locations.min() ?? 0)..<(ends.max() ?? 0)
        }
    }

    func focusedCandidate(requiredPID: pid_t) throws -> BoundCandidate {
        guard client.isTrusted else {
            throw SelectionPermissionRequiredError()
        }
        guard let focused = client.focusedElement(inProcess: requiredPID) else {
            throw MacOSAccessibilityExtractionError.noTextCandidate
        }
        return try candidate(startingAt: focused, requiredPID: requiredPID)
    }

    func hitTestedCandidate(at point: CGPoint, requiredPID: pid_t) throws -> BoundCandidate {
        guard client.isTrusted else {
            throw SelectionPermissionRequiredError()
        }
        guard let hit = client.hitTestedElement(
            at: point,
            inProcess: requiredPID
        ) else {
            throw MacOSAccessibilityExtractionError.noTextCandidate
        }
        return try candidate(startingAt: hit, requiredPID: requiredPID)
    }

    func selectedTextRange(of element: AccessibilityElementHandle) throws -> CFRange {
        let budget = ExtractionBudget(limits: limits)
        try budget.check()
        guard let range = client.selectedTextRange(of: element),
              try validated(range),
              range.length == 0
        else {
            throw MacOSAccessibilityExtractionError.requiredAttributesUnavailable
        }
        return range
    }

    func extract(
        rectangle: SelectionRectangle,
        display: DisplayGeometry,
        from element: AccessibilityElementHandle,
        requiredPID: pid_t
    ) throws -> String {
        let budget = ExtractionBudget(limits: limits)
        try validateBoundElement(element, requiredPID: requiredPID, budget: budget)
        let value = try snapshot(from: element, budget: budget)
        try ensureNoSecureDescendants(of: element, budget: budget)
        try validateBoundElement(element, requiredPID: requiredPID, budget: budget)
        switch CoordinateGridMapper().map(
            selection: rectangle,
            display: display,
            grid: value.grid,
            visualLines: value.lines,
            policy: GridMappingPolicy()
        ) {
        case let .selection(selection):
            return selection.plainText
        case .empty:
            return ""
        case let .unsupported(reason):
            throw MacOSAccessibilityExtractionError.unsupportedMapping(reason)
        }
    }

    func validateBoundElement(
        _ element: AccessibilityElementHandle,
        requiredPID: pid_t,
        budget: ExtractionBudget
    ) throws {
        guard client.isTrusted else {
            throw SelectionPermissionRequiredError()
        }
        guard try checkedPID(of: element, budget: budget) == requiredPID else {
            throw MacOSAccessibilityExtractionError.targetMismatch
        }
        _ = try candidateChain(
            startingAt: element,
            requiredPID: requiredPID,
            budget: budget
        )
        guard let focused = client.focusedElement(inProcess: requiredPID),
              try candidateChain(
                  startingAt: focused,
                  requiredPID: requiredPID,
                  budget: budget
              ).contains(where: { client.isSameElement($0, element) })
        else {
            throw MacOSAccessibilityExtractionError.targetMismatch
        }
    }

    func candidate(
        startingAt element: AccessibilityElementHandle,
        requiredPID: pid_t,
        requiredWindow: AccessibilityElementHandle? = nil
    ) throws -> BoundCandidate {
        guard client.isTrusted else {
            throw SelectionPermissionRequiredError()
        }
        let budget = ExtractionBudget(limits: limits)
        guard try checkedPID(of: element, budget: budget) == requiredPID else {
            throw MacOSAccessibilityExtractionError.targetMismatch
        }
        let chain = try candidateChain(
            startingAt: element,
            requiredPID: requiredPID,
            budget: budget
        )
        var lastError: MacOSAccessibilityExtractionError = .requiredAttributesUnavailable
        for element in chain {
            do {
                if let requiredWindow {
                    guard let candidateWindow = client.window(of: element),
                          client.isSameElement(candidateWindow, requiredWindow)
                    else {
                        throw MacOSAccessibilityExtractionError.targetMismatch
                    }
                }
                let value = try snapshot(from: element, budget: budget)
                try ensureNoSecureDescendants(of: element, budget: budget)
                return BoundCandidate(element: element, grid: value.grid, lines: value.lines)
            } catch let error as MacOSAccessibilityExtractionError {
                switch error {
                case .requiredAttributesUnavailable, .visibleRangeUnavailable,
                     .lineGeometryUnavailable, .unstableGeometry:
                    lastError = error
                default:
                    throw error
                }
            }
        }
        throw lastError
    }

    private struct TextSnapshot {
        let grid: TextGridGeometry
        let lines: [VisualLine]
    }

    private struct MeasuredLine {
        let text: String
        let sourceRange: CFRange
        let bounds: CGRect
        let characterWidths: [Double]
        let leadingCellOffset: Int
    }

    private func checkedPID(
        of element: AccessibilityElementHandle,
        budget: ExtractionBudget
    ) throws -> pid_t {
        try budget.check()
        guard let pid = client.pid(of: element), pid > 0 else {
            throw MacOSAccessibilityExtractionError.targetMismatch
        }
        return pid
    }

    private func candidateChain(
        startingAt element: AccessibilityElementHandle,
        requiredPID: pid_t,
        budget: ExtractionBudget
    ) throws -> [AccessibilityElementHandle] {
        var chain: [AccessibilityElementHandle] = []
        var visited: [AccessibilityElementHandle] = []
        var current: AccessibilityElementHandle? = element
        var canCollectCandidates = true

        while let candidate = current {
            try budget.check()
            let candidatePID = client.pid(of: candidate)
            if let candidatePID, candidatePID != requiredPID {
                break
            }
            client.setMessagingTimeout(limits.perMessageTimeout, for: candidate)
            guard visited.count < limits.maximumCandidates else {
                throw MacOSAccessibilityExtractionError.resourceLimitExceeded
            }
            visited.append(candidate)

            if try isSecure(candidate, budget: budget) {
                // A secure ancestor protects its complete descendant chain. Reject
                // before snapshotting any readable child in that chain.
                throw MacOSAccessibilityExtractionError.secureTextElement
            }

            if candidatePID == requiredPID, canCollectCandidates {
                chain.append(candidate)
            } else {
                // Continue only to prove that skipped ancestors are not secure.
                // Elements across an unresolved PID boundary are never text candidates.
                canCollectCandidates = false
            }

            try budget.check()
            guard let parent = client.parent(of: candidate),
                  !visited.contains(where: { client.isSameElement($0, parent) })
            else {
                break
            }
            current = parent
        }

        return chain
    }

    private func authorizedFocusedFallbackPID(
        _ focused: AccessibilityElementHandle,
        targetPID: pid_t?,
        selectionCenter: CGPoint,
        budget: ExtractionBudget
    ) throws -> pid_t? {
        let focusedPID = try checkedPID(of: focused, budget: budget)
        client.setMessagingTimeout(limits.perMessageTimeout, for: focused)
        if let targetPID, focusedPID != targetPID {
            return nil
        }
        try budget.check()
        guard let frame = client.frame(of: focused),
              frame.width >= 0,
              frame.height >= 0
        else {
            return nil
        }
        return frame.insetBy(dx: -1, dy: -1).contains(selectionCenter) ? focusedPID : nil
    }

    private func isSecure(
        _ element: AccessibilityElementHandle,
        budget: ExtractionBudget
    ) throws -> Bool {
        try budget.check()
        let role = client.role(of: element) ?? ""
        try budget.check()
        let subrole = client.subrole(of: element) ?? ""
        if subrole == (kAXSecureTextFieldSubrole as String) {
            return true
        }
        return [role, subrole].contains(where: {
            let value = $0.lowercased()
            return value.contains("secure") && value.contains("text")
        })
    }

    private func snapshot(
        from element: AccessibilityElementHandle,
        budget: ExtractionBudget
    ) throws -> TextSnapshot {
        try ensureNoSecureDescendants(of: element, budget: budget)
        try budget.check()
        let parameterizedNames = client.parameterizedAttributeNames(of: element)
        guard parameterizedNames.contains(kAXStringForRangeParameterizedAttribute),
              parameterizedNames.contains(kAXBoundsForRangeParameterizedAttribute),
              parameterizedNames.contains(kAXLineForIndexParameterizedAttribute),
              parameterizedNames.contains(kAXRangeForLineParameterizedAttribute)
        else {
            throw MacOSAccessibilityExtractionError.requiredAttributesUnavailable
        }

        let visible = try visibleCharacterRange(element, budget: budget)
        let visibleEnd = try checkedEnd(of: visible)
        guard visible.length > 0 else {
            throw MacOSAccessibilityExtractionError.visibleRangeUnavailable
        }
        let lastVisibleIndex = visibleEnd - 1

        try budget.check()
        guard let firstLine = client.line(for: visible.location, in: element) else {
            throw MacOSAccessibilityExtractionError.lineGeometryUnavailable
        }
        try budget.check()
        guard let lastLine = client.line(for: lastVisibleIndex, in: element),
              firstLine >= 0,
              lastLine >= firstLine
        else {
            throw MacOSAccessibilityExtractionError.lineGeometryUnavailable
        }

        let (lineDistance, overflow) = lastLine.subtractingReportingOverflow(firstLine)
        guard !overflow else {
            throw MacOSAccessibilityExtractionError.resourceLimitExceeded
        }
        let (lineCount, countOverflow) = lineDistance.addingReportingOverflow(1)
        guard !countOverflow, lineCount <= limits.maximumVisualLines else {
            throw MacOSAccessibilityExtractionError.resourceLimitExceeded
        }

        var measured: [MeasuredLine] = []
        var decodedCharacterCount = 0
        for lineNumber in firstLine...lastLine {
            try budget.check()
            guard let rawRange = client.range(forLine: lineNumber, in: element),
                  try validated(rawRange),
                  let lineRange = try intersection(rawRange, visible),
                  lineRange.length > 0
            else {
                continue
            }

            try budget.check()
            guard let rawText = client.string(for: lineRange, in: element) else {
                continue
            }
            let returnedLength = rawText.utf16.count
            let (nextDecodedCount, decodedOverflow) = decodedCharacterCount
                .addingReportingOverflow(returnedLength)
            guard returnedLength <= lineRange.length,
                  !decodedOverflow,
                  nextDecodedCount <= limits.maximumVisibleCharacters
            else {
                throw MacOSAccessibilityExtractionError.resourceLimitExceeded
            }
            decodedCharacterCount = nextDecodedCount

            let text = removingLineTerminator(from: rawText)
            let contentLength = min(lineRange.length, text.utf16.count)
            let contentRange = CFRange(location: lineRange.location, length: contentLength)
            let leadingCellOffset = lineRange.location - rawRange.location
            guard leadingCellOffset <= limits.maximumVisibleCharacters else {
                throw MacOSAccessibilityExtractionError.resourceLimitExceeded
            }
            try budget.check()
            let contentBounds = contentLength > 0
                ? client.bounds(for: contentRange, in: element)
                : nil
            try budget.check()
            guard let bounds = contentBounds ?? client.bounds(for: lineRange, in: element),
                  bounds.width >= 0,
                  bounds.height > 0
            else {
                continue
            }

            let widths = try representativeCharacterWidths(
                text: text,
                sourceLocation: lineRange.location,
                element: element,
                budget: budget
            )
            measured.append(
                MeasuredLine(
                    text: text,
                    sourceRange: contentRange,
                    bounds: bounds,
                    characterWidths: widths,
                    leadingCellOffset: leadingCellOffset
                )
            )
        }

        measured.sort { $0.bounds.minY < $1.bounds.minY }
        guard !measured.isEmpty else {
            throw MacOSAccessibilityExtractionError.lineGeometryUnavailable
        }

        let measuredCharacterWidths = measured.flatMap(\.characterWidths).filter { $0 > 0 }
        let characterWidths = measuredCharacterWidths.isEmpty
            ? measured.compactMap { line -> Double? in
                let cellCount = line.text.utf16.count
                guard cellCount > 0, line.bounds.width > 0 else {
                    return nil
                }
                return line.bounds.width / Double(cellCount)
            }
            : measuredCharacterWidths
        guard let characterWidth = stableMedian(characterWidths, relativeTolerance: 0.15) else {
            throw MacOSAccessibilityExtractionError.unstableGeometry
        }

        let topEdges = measured.map { Double($0.bounds.minY) }
        let lineGaps = zip(topEdges, topEdges.dropFirst())
            .map { $1 - $0 }
            .filter { $0 > 0 }
        let fallbackHeights = measured.map { Double($0.bounds.height) }.filter { $0 > 0 }
        guard let lineHeight = stableMedian(
            lineGaps.isEmpty ? fallbackHeights : lineGaps,
            relativeTolerance: 0.2
        ) else {
            throw MacOSAccessibilityExtractionError.unstableGeometry
        }

        let leftEdges = measured.map {
            Double($0.bounds.minX) - (Double($0.leadingCellOffset) * characterWidth)
        }
        guard let minimumX = leftEdges.min(),
              (leftEdges.max() ?? minimumX) - minimumX <= max(2, characterWidth * 0.25)
        else {
            throw MacOSAccessibilityExtractionError.unstableGeometry
        }

        return TextSnapshot(
            grid: TextGridGeometry(
                originX: minimumX,
                originY: Double(measured[0].bounds.minY),
                characterWidth: characterWidth,
                lineHeight: lineHeight
            ),
            lines: try alignedVisualLines(from: measured, budget: budget)
        )
    }

    private func ensureNoSecureDescendants(
        of element: AccessibilityElementHandle,
        budget: ExtractionBudget
    ) throws {
        try budget.check()
        client.setMessagingTimeout(limits.perMessageTimeout, for: element)
        guard let rootChildCount = client.childCount(of: element),
              rootChildCount <= limits.maximumCandidates,
              let rootChildren = client.children(
                  of: element,
                  limit: limits.maximumCandidates
              ),
              rootChildren.count == rootChildCount
        else {
            throw MacOSAccessibilityExtractionError.resourceLimitExceeded
        }
        try budget.check()
        var pending = rootChildren
        var visited: [AccessibilityElementHandle] = []
        while let candidate = pending.popLast() {
            try budget.check()
            guard visited.count < limits.maximumCandidates else {
                throw MacOSAccessibilityExtractionError.resourceLimitExceeded
            }
            if visited.contains(where: { client.isSameElement($0, candidate) }) {
                continue
            }
            visited.append(candidate)
            client.setMessagingTimeout(limits.perMessageTimeout, for: candidate)
            if try isSecure(candidate, budget: budget) {
                throw MacOSAccessibilityExtractionError.secureTextElement
            }
            let remaining = limits.maximumCandidates - visited.count - pending.count
            guard remaining >= 0,
                  let childCount = client.childCount(of: candidate),
                  childCount <= remaining,
                  let children = client.children(of: candidate, limit: remaining),
                  children.count == childCount
            else {
                throw MacOSAccessibilityExtractionError.resourceLimitExceeded
            }
            try budget.check()
            pending.append(contentsOf: children)
        }
    }

    private func alignedVisualLines(
        from measured: [MeasuredLine],
        budget: ExtractionBudget
    ) throws -> [VisualLine] {
        var totalCellCount = 0
        return try measured.map { line in
            try budget.check()
            let (lineCellCount, lineOverflow) = line.leadingCellOffset
                .addingReportingOverflow(line.text.utf16.count)
            let (nextTotal, totalOverflow) = totalCellCount
                .addingReportingOverflow(lineCellCount)
            guard !lineOverflow,
                  !totalOverflow,
                  nextTotal <= limits.maximumVisibleCharacters
            else {
                throw MacOSAccessibilityExtractionError.resourceLimitExceeded
            }
            totalCellCount = nextTotal
            return VisualLine(
                text: String(repeating: " ", count: line.leadingCellOffset) + line.text,
                sourceLocation: line.sourceRange.location,
                sourceLength: line.sourceRange.length
            )
        }
    }

    private func visibleCharacterRange(
        _ element: AccessibilityElementHandle,
        budget: ExtractionBudget
    ) throws -> CFRange {
        try budget.check()
        if let range = client.visibleCharacterRange(of: element) {
            guard try validated(range) else {
                throw MacOSAccessibilityExtractionError.visibleRangeUnavailable
            }
            guard range.length <= limits.maximumVisibleCharacters else {
                throw MacOSAccessibilityExtractionError.visibleRangeTooLarge(
                    limit: limits.maximumVisibleCharacters
                )
            }
            return range
        }

        try budget.check()
        if let count = client.numberOfCharacters(in: element), count >= 0 {
            guard count <= limits.maximumVisibleCharacters else {
                throw MacOSAccessibilityExtractionError.visibleRangeTooLarge(
                    limit: limits.maximumVisibleCharacters
                )
            }
            return CFRange(location: 0, length: count)
        }

        throw MacOSAccessibilityExtractionError.visibleRangeUnavailable
    }

    private func representativeCharacterWidths(
        text: String,
        sourceLocation: Int,
        element: AccessibilityElementHandle,
        budget: ExtractionBudget
    ) throws -> [Double] {
        var seen: Set<UInt16> = []
        var sampleOffsets: [Int] = []
        for (offset, codeUnit) in text.utf16.enumerated() {
            guard codeUnit >= 0x20, codeUnit <= 0x7e, codeUnit != 0x09 else {
                continue
            }
            if seen.insert(codeUnit).inserted {
                sampleOffsets.append(offset)
            }
            if sampleOffsets.count == limits.maximumWidthSamplesPerLine {
                break
            }
        }

        var widths: [Double] = []
        for offset in sampleOffsets {
            let (location, overflow) = sourceLocation.addingReportingOverflow(offset)
            guard !overflow else {
                throw MacOSAccessibilityExtractionError.resourceLimitExceeded
            }
            try budget.check()
            if let bounds = client.bounds(
                for: CFRange(location: location, length: 1),
                in: element
            ), bounds.width > 0 {
                widths.append(bounds.width)
            }
        }
        return widths
    }

    private func validated(_ range: CFRange) throws -> Bool {
        guard range.location >= 0, range.length >= 0 else {
            return false
        }
        _ = try checkedEnd(of: range)
        return true
    }

    private func checkedEnd(of range: CFRange) throws -> Int {
        guard range.location >= 0, range.length >= 0 else {
            throw MacOSAccessibilityExtractionError.resourceLimitExceeded
        }
        let (end, overflow) = range.location.addingReportingOverflow(range.length)
        guard !overflow else {
            throw MacOSAccessibilityExtractionError.resourceLimitExceeded
        }
        return end
    }

    private func intersection(_ lhs: CFRange, _ rhs: CFRange) throws -> CFRange? {
        let lhsEnd = try checkedEnd(of: lhs)
        let rhsEnd = try checkedEnd(of: rhs)
        let lower = max(lhs.location, rhs.location)
        let upper = min(lhsEnd, rhsEnd)
        guard lower < upper else {
            return nil
        }
        return CFRange(location: lower, length: upper - lower)
    }

    private func removingLineTerminator(from text: String) -> String {
        var result = text
        while result.last == "\n" || result.last == "\r" {
            result.removeLast()
        }
        return result
    }

    private func stableMedian(
        _ values: [Double],
        relativeTolerance: Double
    ) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else {
            return nil
        }
        let median: Double
        if sorted.count.isMultiple(of: 2) {
            median = (sorted[(sorted.count / 2) - 1] + sorted[sorted.count / 2]) / 2
        } else {
            median = sorted[sorted.count / 2]
        }
        guard median > 0 else {
            return nil
        }
        let tolerance = median * relativeTolerance
        guard sorted.allSatisfy({ abs($0 - median) <= tolerance }) else {
            return nil
        }
        return median
    }
}

final class ExtractionBudget: @unchecked Sendable {
    private let limits: AccessibilityExtractionLimits
    private let startUptime: TimeInterval
    private var callCount = 0

    init(limits: AccessibilityExtractionLimits) {
        self.limits = limits
        startUptime = ProcessInfo.processInfo.systemUptime
    }

    func check() throws {
        if Task.isCancelled {
            throw CancellationError()
        }
        callCount += 1
        guard callCount <= limits.maximumAXCalls else {
            throw MacOSAccessibilityExtractionError.resourceLimitExceeded
        }
        guard ProcessInfo.processInfo.systemUptime - startUptime <= limits.totalTimeout else {
            throw MacOSAccessibilityExtractionError.timedOut
        }
    }
}

final class MacOSAccessibilityTextExtractor: RectangularTextExtracting, @unchecked Sendable {
    private let client: any MacOSAccessibilityClient
    private let limits: AccessibilityExtractionLimits

    init(
        client: any MacOSAccessibilityClient = SystemMacOSAccessibilityClient(),
        limits: AccessibilityExtractionLimits = AccessibilityExtractionLimits()
    ) {
        self.client = client
        self.limits = limits
    }

    func extractText(in rectangle: SelectionRectangle) async throws -> String {
        guard client.isTrusted else {
            throw SelectionPermissionRequiredError()
        }
        let display = try await MainActor.run {
            try Self.displayGeometry(for: rectangle.displayID)
        }
        return try await extractText(in: rectangle, display: display)
    }

    func extractText(
        in rectangle: SelectionRectangle,
        display: DisplayGeometry
    ) async throws -> String {
        let engine = MacOSAccessibilityExtractionEngine(client: client, limits: limits)
        let extractionTask = Task.detached(priority: .userInitiated) {
            try engine.extract(rectangle: rectangle, display: display)
        }
        return try await withTaskCancellationHandler {
            try await extractionTask.value
        } onCancel: {
            extractionTask.cancel()
        }
    }

    @MainActor
    private static func displayGeometry(for displayID: UInt32) throws -> DisplayGeometry {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[screenNumberKey] as? UInt32) == displayID
        }) else {
            throw MacOSAccessibilityExtractionError.displayUnavailable
        }

        let appKitFrame = screen.frame
        let coreGraphicsBounds = CGDisplayBounds(displayID)
        return DisplayGeometry(
            displayID: displayID,
            appKitFrame: ScreenRectangle(
                x: appKitFrame.origin.x,
                y: appKitFrame.origin.y,
                width: appKitFrame.width,
                height: appKitFrame.height
            ),
            coreGraphicsBounds: ScreenRectangle(
                x: coreGraphicsBounds.origin.x,
                y: coreGraphicsBounds.origin.y,
                width: coreGraphicsBounds.width,
                height: coreGraphicsBounds.height
            ),
            backingScale: screen.backingScaleFactor
        )
    }
}

struct SystemMacOSAccessibilityClient: MacOSAccessibilityClient {
    var isTrusted: Bool { AXIsProcessTrusted() }

    func hitTestedElement(
        at point: CGPoint,
        inProcess processIdentifier: pid_t?
    ) -> AccessibilityElementHandle? {
        let root = processIdentifier.map(AXUIElementCreateApplication)
            ?? AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            root,
            Float(point.x),
            Float(point.y),
            &element
        ) == .success,
        let element
        else {
            return nil
        }
        return AccessibilityElementHandle(rawElement: element)
    }

    func focusedElement(inProcess processIdentifier: pid_t?) -> AccessibilityElementHandle? {
        let root = processIdentifier.map(AXUIElementCreateApplication)
            ?? AXUIElementCreateSystemWide()
        guard let value = copyAttribute(root, kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return AccessibilityElementHandle(rawElement: value as! AXUIElement)
    }

    func parent(of element: AccessibilityElementHandle) -> AccessibilityElementHandle? {
        guard let rawElement = element.rawElement,
              let value = copyAttribute(rawElement, kAXParentAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return AccessibilityElementHandle(rawElement: value as! AXUIElement)
    }

    func childCount(of element: AccessibilityElementHandle) -> Int? {
        guard let rawElement = element.rawElement else {
            return nil
        }
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(
            rawElement,
            kAXChildrenAttribute as CFString,
            &count
        ) == .success else {
            return nil
        }
        return count >= 0 ? count : nil
    }

    func children(
        of element: AccessibilityElementHandle,
        limit: Int
    ) -> [AccessibilityElementHandle]? {
        guard let rawElement = element.rawElement, limit >= 0 else {
            return nil
        }
        if limit == 0 {
            return []
        }
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(
            rawElement,
            kAXChildrenAttribute as CFString,
            0,
            limit,
            &values
        ) == .success,
        let values = values as? [AXUIElement]
        else {
            return nil
        }
        return values.map(AccessibilityElementHandle.init(rawElement:))
    }

    func window(of element: AccessibilityElementHandle) -> AccessibilityElementHandle? {
        guard let rawElement = element.rawElement else {
            return nil
        }
        if stringAttribute(element, kAXRoleAttribute) == (kAXWindowRole as String) {
            return element
        }
        guard let value = copyAttribute(rawElement, kAXWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return AccessibilityElementHandle(rawElement: value as! AXUIElement)
    }

    func windowCount(inProcess processIdentifier: pid_t) -> Int? {
        let application = AXUIElementCreateApplication(processIdentifier)
        _ = AXUIElementSetMessagingTimeout(application, 1)
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(
            application,
            kAXWindowsAttribute as CFString,
            &count
        ) == .success
        else {
            return nil
        }
        return count >= 0 ? count : nil
    }

    func windows(
        inProcess processIdentifier: pid_t,
        limit: Int
    ) -> [AccessibilityElementHandle]? {
        guard limit >= 0 else {
            return nil
        }
        if limit == 0 {
            return []
        }
        let application = AXUIElementCreateApplication(processIdentifier)
        _ = AXUIElementSetMessagingTimeout(application, 1)
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(
            application,
            kAXWindowsAttribute as CFString,
            0,
            limit,
            &values
        ) == .success,
        let values = values as? [AXUIElement]
        else {
            return nil
        }
        return values.map(AccessibilityElementHandle.init(rawElement:))
    }

    func isSameElement(
        _ lhs: AccessibilityElementHandle,
        _ rhs: AccessibilityElementHandle
    ) -> Bool {
        guard let lhs = lhs.rawElement, let rhs = rhs.rawElement else {
            return lhs.testIdentifier == rhs.testIdentifier
        }
        return CFEqual(lhs, rhs)
    }

    func pid(of element: AccessibilityElementHandle) -> pid_t? {
        guard let rawElement = element.rawElement else {
            return nil
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(rawElement, &pid) == .success else {
            return nil
        }
        return pid
    }

    func frame(of element: AccessibilityElementHandle) -> CGRect? {
        guard let rawElement = element.rawElement,
              let positionValue = copyAttribute(rawElement, kAXPositionAttribute),
              let sizeValue = copyAttribute(rawElement, kAXSizeAttribute),
              let position = pointFromAXValue(positionValue),
              let size = sizeFromAXValue(sizeValue)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    func role(of element: AccessibilityElementHandle) -> String? {
        stringAttribute(element, kAXRoleAttribute)
    }

    func subrole(of element: AccessibilityElementHandle) -> String? {
        stringAttribute(element, kAXSubroleAttribute)
    }

    func setMessagingTimeout(_ seconds: Float, for element: AccessibilityElementHandle) {
        guard let rawElement = element.rawElement else {
            return
        }
        _ = AXUIElementSetMessagingTimeout(rawElement, seconds)
    }

    func parameterizedAttributeNames(of element: AccessibilityElementHandle) -> [String] {
        guard let rawElement = element.rawElement else {
            return []
        }
        var names: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(rawElement, &names) == .success,
              let names = names as? [String]
        else {
            return []
        }
        return names
    }

    func visibleCharacterRange(of element: AccessibilityElementHandle) -> CFRange? {
        guard let rawElement = element.rawElement,
              let value = copyAttribute(rawElement, kAXVisibleCharacterRangeAttribute)
        else {
            return nil
        }
        return rangeFromAXValue(value)
    }

    func selectedTextRange(of element: AccessibilityElementHandle) -> CFRange? {
        guard let rawElement = element.rawElement,
              let value = copyAttribute(rawElement, kAXSelectedTextRangeAttribute)
        else {
            return nil
        }
        return rangeFromAXValue(value)
    }

    func numberOfCharacters(in element: AccessibilityElementHandle) -> Int? {
        guard let rawElement = element.rawElement,
              let value = copyAttribute(rawElement, kAXNumberOfCharactersAttribute)
        else {
            return nil
        }
        return (value as? NSNumber)?.intValue
    }

    func line(for index: Int, in element: AccessibilityElementHandle) -> Int? {
        guard let rawElement = element.rawElement,
              let value = copyParameterizedAttribute(
                  rawElement,
                  kAXLineForIndexParameterizedAttribute,
                  parameter: NSNumber(value: index)
              )
        else {
            return nil
        }
        return (value as? NSNumber)?.intValue
    }

    func range(forLine line: Int, in element: AccessibilityElementHandle) -> CFRange? {
        guard let rawElement = element.rawElement,
              let value = copyParameterizedAttribute(
                  rawElement,
                  kAXRangeForLineParameterizedAttribute,
                  parameter: NSNumber(value: line)
              )
        else {
            return nil
        }
        return rangeFromAXValue(value)
    }

    func string(for range: CFRange, in element: AccessibilityElementHandle) -> String? {
        guard let rawElement = element.rawElement,
              let parameter = rangeAXValue(range),
              let value = copyParameterizedAttribute(
                  rawElement,
                  kAXStringForRangeParameterizedAttribute,
                  parameter: parameter
              )
        else {
            return nil
        }
        return value as? String
    }

    func bounds(for range: CFRange, in element: AccessibilityElementHandle) -> CGRect? {
        guard let rawElement = element.rawElement,
              let parameter = rangeAXValue(range),
              let value = copyParameterizedAttribute(
                  rawElement,
                  kAXBoundsForRangeParameterizedAttribute,
                  parameter: parameter
              )
        else {
            return nil
        }
        return rectangleFromAXValue(value)
    }

    private func stringAttribute(
        _ element: AccessibilityElementHandle,
        _ attribute: String
    ) -> String? {
        guard let rawElement = element.rawElement else {
            return nil
        }
        return copyAttribute(rawElement, attribute) as? String
    }

    private func copyAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func copyParameterizedAttribute(
        _ element: AXUIElement,
        _ attribute: String,
        parameter: CFTypeRef
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute as CFString,
            parameter,
            &value
        ) == .success else {
            return nil
        }
        return value
    }

    private func rangeFromAXValue(_ value: CFTypeRef) -> CFRange? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }
        var range = CFRange(location: 0, length: 0)
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private func rectangleFromAXValue(_ value: CFTypeRef) -> CGRect? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgRect else {
            return nil
        }
        var rectangle = CGRect.zero
        return AXValueGetValue(axValue, .cgRect, &rectangle) ? rectangle : nil
    }

    private func pointFromAXValue(_ value: CFTypeRef) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func sizeFromAXValue(_ value: CFTypeRef) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private func rangeAXValue(_ range: CFRange) -> AXValue? {
        var mutableRange = range
        return AXValueCreate(.cfRange, &mutableRange)
    }
}
