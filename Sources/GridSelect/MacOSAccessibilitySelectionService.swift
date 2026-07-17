import Carbon.HIToolbox
import CoreGraphics
import Foundation
import GridSelectCore

enum MacOSCaretCaptureResult: Sendable {
    case captured(GridCaretCandidate)
    case unavailable
    case rejected(SelectionSourceFailure)
}

/// Owns the exact AX element selected during activation. Tokens are process-local,
/// non-derivable identifiers; extraction never performs a second hit test.
final class MacOSAccessibilitySelectionService: RectangularTextExtracting, @unchecked Sendable {
    private struct Entry: @unchecked Sendable {
        let activation: GridActivation
        let sessionIdentity: SelectionSessionIdentity
        let source: SelectionSourceIdentity
        let sourceWindowFrame: ScreenRectangle
        let element: AccessibilityElementHandle
        let window: AccessibilityElementHandle
        var bindingOrigins: Set<SelectionBindingOrigin>
        var mouseBindingLeaseCount: UInt64
    }

    private let client: any MacOSAccessibilityClient
    private let limits: AccessibilityExtractionLimits
    private let windowValidator: @Sendable (
        SelectionSourceIdentity,
        ScreenRectangle
    ) -> Bool
    private let secureInputEnabled: @Sendable () -> Bool
    private let lock = NSLock()
    private var nextIdentity: UInt64 = 0
    private var entries: [SelectionElementIdentity: Entry] = [:]

    init(
        client: any MacOSAccessibilityClient = SystemMacOSAccessibilityClient(),
        limits: AccessibilityExtractionLimits = AccessibilityExtractionLimits(),
        windowValidator: (@Sendable (
            SelectionSourceIdentity,
            ScreenRectangle
        ) -> Bool)? = nil,
        secureInputEnabled: @escaping @Sendable () -> Bool = {
            IsSecureEventInputEnabled()
        }
    ) {
        self.client = client
        self.limits = limits
        self.windowValidator = windowValidator ?? Self.sourceWindowStillMatches
        self.secureInputEnabled = secureInputEnabled
    }

    func captureCaretCandidate(
        activation: GridActivation,
        sessionIdentity: SelectionSessionIdentity,
        source: SelectionSourceIdentity,
        sourceWindowFrame: ScreenRectangle,
        displays: [DisplayGeometry]
    ) -> MacOSCaretCaptureResult {
        let engine = MacOSAccessibilityExtractionEngine(client: client, limits: limits)
        do {
            guard !secureInputEnabled() else {
                return .rejected(.secureInputUnsupported)
            }
            guard client.isTrusted else {
                return .rejected(.permissionRequired)
            }
            guard let focused = client.focusedElement(
                inProcess: pid_t(source.processIdentifier),
                messagingTimeout: limits.perMessageTimeout
            ) else {
                return .unavailable
            }
            client.setMessagingTimeout(limits.perMessageTimeout, for: focused)
            guard let preflightWindow = client.window(of: focused) else {
                return .unavailable
            }
            guard windowValidator(source, sourceWindowFrame),
                  window(preflightWindow, matches: source, frame: sourceWindowFrame)
            else {
                return .rejected(.sourceContextInvalid)
            }
            let candidate = try engine.candidate(
                startingAt: focused,
                requiredPID: pid_t(source.processIdentifier),
                requiredWindow: preflightWindow
            )
            guard !candidate.lines.contains(where: { $0.text.contains("\t") }) else {
                return .rejected(.unsupportedText)
            }
            guard let sourceWindow = client.window(of: candidate.element),
                  client.isSameElement(sourceWindow, preflightWindow),
                  window(sourceWindow, matches: source, frame: sourceWindowFrame),
                  let selectedRange = try? engine.selectedTextRange(of: candidate.element),
                  client.bounds(for: selectedRange, in: candidate.element) != nil,
                  let display = display(containing: candidate.grid, in: displays),
                  let anchor = caretAnchor(
                      location: selectedRange.location,
                      lines: candidate.lines
                  ),
                  let viewport = viewport(
                      grid: candidate.grid,
                      rowCount: candidate.lines.count,
                      display: display
                  )
            else {
                return .unavailable
            }
            try engine.validateBoundElement(
                candidate.element,
                requiredPID: pid_t(source.processIdentifier),
                budget: ExtractionBudget(limits: limits),
                requiresFocus: true
            )
            guard !secureInputEnabled() else {
                return .rejected(.secureInputUnsupported)
            }
            guard windowValidator(source, sourceWindowFrame),
                  let finalWindow = client.window(of: candidate.element),
                  client.isSameElement(finalWindow, sourceWindow),
                  window(finalWindow, matches: source, frame: sourceWindowFrame)
            else {
                return .rejected(.sourceContextInvalid)
            }
            let identity = register(
                candidate.element,
                activation: activation,
                sessionIdentity: sessionIdentity,
                source: source,
                sourceWindowFrame: sourceWindowFrame,
                window: sourceWindow,
                bindingOrigin: .keyboardCaret
            )
            return .captured(
                GridCaretCandidate(
                    element: identity,
                    anchor: anchor,
                    sourceRange: selectedRange.location..<selectedRange.location,
                    displayID: display.displayID,
                    viewport: viewport
                )
            )
        } catch is SelectionPermissionRequiredError {
            return .rejected(.permissionRequired)
        } catch MacOSAccessibilityExtractionError.secureTextElement {
            return .rejected(.secureInputUnsupported)
        } catch MacOSAccessibilityExtractionError.targetMismatch {
            return .rejected(.sourceContextInvalid)
        } catch {
            return .unavailable
        }
    }

    func resolveMouseAnchor(
        at appKitScreenPoint: SelectionPoint,
        sourceContext: ActivationSourceContext
    ) -> MacOSGridMouseAnchorResolution {
        guard !Task.isCancelled else {
            return .unavailable
        }
        guard sourceContext.sessionIdentity != nil else {
            return .rejected(.sourceContextInvalid)
        }
        guard let display = sourceContext.displays.first(where: {
            $0.appKitFrame.minX <= appKitScreenPoint.x
                && appKitScreenPoint.x < $0.appKitFrame.maxX
                && $0.appKitFrame.minY <= appKitScreenPoint.y
                && appKitScreenPoint.y < $0.appKitFrame.maxY
        }) else {
            return .rejected(.sourceContextInvalid)
        }
        let canonicalPoint = CGPoint(
            x: display.coreGraphicsBounds.minX
                + (appKitScreenPoint.x - display.appKitFrame.minX),
            y: display.coreGraphicsBounds.minY
                + (display.appKitFrame.maxY - appKitScreenPoint.y)
        )
        let engine = MacOSAccessibilityExtractionEngine(client: client, limits: limits)
        do {
            guard !secureInputEnabled() else {
                return .rejected(.secureInputUnsupported)
            }
            guard !Task.isCancelled else {
                return .unavailable
            }
            guard client.isTrusted else {
                return .rejected(.permissionRequired)
            }
            guard let hit = client.hitTestedElement(
                at: canonicalPoint,
                inProcess: pid_t(sourceContext.source.processIdentifier),
                messagingTimeout: limits.perMessageTimeout
            ) else {
                return .rejected(.sourceContextInvalid)
            }
            client.setMessagingTimeout(limits.perMessageTimeout, for: hit)
            guard let preflightWindow = client.window(of: hit),
            windowValidator(
                sourceContext.source,
                sourceContext.sourceWindowFrame
            ),
            window(
                preflightWindow,
                matches: sourceContext.source,
                frame: sourceContext.sourceWindowFrame
            )
            else {
                return .rejected(.sourceContextInvalid)
            }
            let candidate = try engine.candidate(
                startingAt: hit,
                requiredPID: pid_t(sourceContext.source.processIdentifier),
                requiredWindow: preflightWindow
            )
            guard !candidate.lines.contains(where: { $0.text.contains("\t") }) else {
                return .rejected(.unsupportedText)
            }
            guard let sourceWindow = client.window(of: candidate.element),
                  client.isSameElement(sourceWindow, preflightWindow),
                  window(
                      sourceWindow,
                      matches: sourceContext.source,
                      frame: sourceContext.sourceWindowFrame
                  ),
                  let viewport = viewport(
                      grid: candidate.grid,
                      rowCount: candidate.lines.count,
                      display: display
                  ),
                  let anchor = viewport.boundary(
                      at: appKitScreenPoint,
                      role: .initialAnchor
                  )
            else {
                return .rejected(.sourceContextInvalid)
            }
            try engine.validateBoundElement(
                candidate.element,
                requiredPID: pid_t(sourceContext.source.processIdentifier),
                budget: ExtractionBudget(limits: limits),
                requiresFocus: false
            )
            guard !secureInputEnabled() else {
                return .rejected(.secureInputUnsupported)
            }
            guard !Task.isCancelled else {
                return .unavailable
            }
            guard windowValidator(
                      sourceContext.source,
                      sourceContext.sourceWindowFrame
                  ),
                  let finalWindow = client.window(of: candidate.element),
                  client.isSameElement(finalWindow, sourceWindow),
                  window(
                      finalWindow,
                      matches: sourceContext.source,
                      frame: sourceContext.sourceWindowFrame
                  )
            else {
                return .rejected(.sourceContextInvalid)
            }
            guard !Task.isCancelled else {
                return .unavailable
            }
            let identity = register(
                candidate.element,
                activation: sourceContext.activation,
                sessionIdentity: sourceContext.sessionIdentity,
                source: sourceContext.source,
                sourceWindowFrame: sourceContext.sourceWindowFrame,
                window: sourceWindow,
                bindingOrigin: .mouseHit
            )
            return .resolved(
                GridMouseAnchorCandidate(
                    source: sourceContext.source,
                    element: identity,
                    sourceRange: sourceRange(
                        for: anchor,
                        lines: candidate.lines
                    ),
                    viewport: viewport
                )
            )
        } catch is SelectionPermissionRequiredError {
            return .rejected(.permissionRequired)
        } catch MacOSAccessibilityExtractionError.secureTextElement {
            return .rejected(.secureInputUnsupported)
        } catch MacOSAccessibilityExtractionError.targetMismatch {
            return .rejected(.sourceContextInvalid)
        } catch {
            return .rejected(.unsupportedText)
        }
    }

    func extractText(in rectangle: SelectionRectangle) async throws -> String {
        guard !secureInputEnabled() else {
            throw SelectionSourceFailureError(.secureInputUnsupported)
        }
        let extractor = MacOSAccessibilityTextExtractor(client: client, limits: limits)
        let text = try await extractor.extractText(in: rectangle)
        guard !secureInputEnabled() else {
            throw SelectionSourceFailureError(.secureInputUnsupported)
        }
        return text
    }

    func discardMouseAnchor(
        _ candidate: GridMouseAnchorCandidate,
        sourceContext: ActivationSourceContext
    ) {
        lock.withLock {
            guard let sessionIdentity = sourceContext.sessionIdentity,
                  var entry = entries[candidate.element],
                  entry.activation == sourceContext.activation,
                  entry.sessionIdentity == sessionIdentity,
                  entry.source == sourceContext.source,
                  entry.sourceWindowFrame == sourceContext.sourceWindowFrame
            else {
                return
            }
            guard entry.mouseBindingLeaseCount > 0 else {
                return
            }
            entry.mouseBindingLeaseCount -= 1
            if entry.mouseBindingLeaseCount == 0 {
                entry.bindingOrigins.remove(.mouseHit)
            }
            if entry.bindingOrigins.isEmpty {
                entries.removeValue(forKey: candidate.element)
            } else {
                entries[candidate.element] = entry
            }
        }
    }

    func extractText(
        in rectangle: SelectionRectangle,
        boundContext: BoundSelectionContext
    ) async throws -> String {
        guard !secureInputEnabled() else {
            throw SelectionSourceFailureError(.secureInputUnsupported)
        }
        guard let entry = entry(for: boundContext.element),
              registryEntry(entry, matches: boundContext),
              windowValidator(boundContext.source, boundContext.sourceWindowFrame),
              let currentWindow = client.window(of: entry.element),
              client.isSameElement(currentWindow, entry.window),
              window(
                  currentWindow,
                  matches: boundContext.source,
                  frame: boundContext.sourceWindowFrame
              )
        else {
            throw SelectionSourceFailureError(.sourceContextInvalid)
        }
        let engine = MacOSAccessibilityExtractionEngine(client: client, limits: limits)
        let task = Task.detached(priority: .userInitiated) {
            try engine.extract(
                rectangle: rectangle,
                display: boundContext.display,
                from: entry.element,
                requiredPID: pid_t(boundContext.source.processIdentifier),
                requiresFocus: boundContext.bindingOrigin == .keyboardCaret
            )
        }
        let text: String
        do {
            text = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch is SelectionPermissionRequiredError {
            throw SelectionPermissionRequiredError()
        } catch MacOSAccessibilityExtractionError.secureTextElement {
            throw SelectionSourceFailureError(.secureInputUnsupported)
        } catch MacOSAccessibilityExtractionError.targetMismatch {
            throw SelectionSourceFailureError(.sourceContextInvalid)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SelectionSourceFailureError(.unsupportedText)
        }
        guard !secureInputEnabled() else {
            throw SelectionSourceFailureError(.secureInputUnsupported)
        }
        guard let finalEntry = self.entry(for: boundContext.element),
              registryEntry(finalEntry, matches: boundContext),
              windowValidator(boundContext.source, boundContext.sourceWindowFrame),
              let finalWindow = client.window(of: entry.element),
              client.isSameElement(finalWindow, entry.window),
              window(
                  finalWindow,
                  matches: boundContext.source,
                  frame: boundContext.sourceWindowFrame
              )
        else {
            throw SelectionSourceFailureError(.sourceContextInvalid)
        }
        return text
    }

    func discardBoundContexts(for sessionIdentity: SelectionSessionIdentity) async {
        discardBoundContextsSynchronously(for: sessionIdentity)
    }

    func validateCopyAuthorization(
        for boundContext: BoundSelectionContext?
    ) async throws {
        guard !secureInputEnabled() else {
            throw SelectionSourceFailureError(.secureInputUnsupported)
        }
        guard client.isTrusted else {
            throw SelectionPermissionRequiredError()
        }
        guard let boundContext else {
            return
        }
        guard let entry = entry(for: boundContext.element),
              registryEntry(entry, matches: boundContext),
              windowValidator(boundContext.source, boundContext.sourceWindowFrame),
              let currentWindow = client.window(of: entry.element),
              client.isSameElement(currentWindow, entry.window),
              window(
                  currentWindow,
                  matches: boundContext.source,
                  frame: boundContext.sourceWindowFrame
              )
        else {
            throw SelectionSourceFailureError(.sourceContextInvalid)
        }
        let engine = MacOSAccessibilityExtractionEngine(client: client, limits: limits)
        do {
            try engine.validateBoundElement(
                entry.element,
                requiredPID: pid_t(boundContext.source.processIdentifier),
                budget: ExtractionBudget(limits: limits),
                requiresFocus: boundContext.bindingOrigin == .keyboardCaret
            )
        } catch is SelectionPermissionRequiredError {
            throw SelectionPermissionRequiredError()
        } catch MacOSAccessibilityExtractionError.secureTextElement {
            throw SelectionSourceFailureError(.secureInputUnsupported)
        } catch MacOSAccessibilityExtractionError.targetMismatch {
            throw SelectionSourceFailureError(.sourceContextInvalid)
        } catch {
            throw SelectionSourceFailureError(.unsupportedText)
        }
        guard !secureInputEnabled() else {
            throw SelectionSourceFailureError(.secureInputUnsupported)
        }
        guard let finalEntry = self.entry(for: boundContext.element),
              registryEntry(finalEntry, matches: boundContext),
              windowValidator(boundContext.source, boundContext.sourceWindowFrame),
              let finalWindow = client.window(of: entry.element),
              client.isSameElement(finalWindow, entry.window),
              window(
                  finalWindow,
                  matches: boundContext.source,
                  frame: boundContext.sourceWindowFrame
              )
        else {
            throw SelectionSourceFailureError(.sourceContextInvalid)
        }
    }

    func discardBoundContextsSynchronously(
        for sessionIdentity: SelectionSessionIdentity
    ) {
        lock.withLock {
            entries = entries.filter { $0.value.sessionIdentity != sessionIdentity }
        }
    }

    var registeredContextCount: Int {
        lock.withLock { entries.count }
    }

    private func register(
        _ element: AccessibilityElementHandle,
        activation: GridActivation,
        sessionIdentity: SelectionSessionIdentity?,
        source: SelectionSourceIdentity,
        sourceWindowFrame: ScreenRectangle,
        window: AccessibilityElementHandle,
        bindingOrigin: SelectionBindingOrigin
    ) -> SelectionElementIdentity {
        lock.withLock {
            if let sessionIdentity,
               let existing = entries.first(where: {
                   $0.value.sessionIdentity == sessionIdentity
                       && $0.value.source == source
                       && client.isSameElement($0.value.element, element)
               })
            {
                var entry = existing.value
                entry.bindingOrigins.insert(bindingOrigin)
                if bindingOrigin == .mouseHit {
                    guard entry.mouseBindingLeaseCount < UInt64.max else {
                        return allocateEntry(
                            element,
                            activation: activation,
                            sessionIdentity: sessionIdentity,
                            source: source,
                            sourceWindowFrame: sourceWindowFrame,
                            window: window,
                            bindingOrigin: bindingOrigin
                        )
                    }
                    entry.mouseBindingLeaseCount += 1
                }
                entries[existing.key] = entry
                return existing.key
            }
            return allocateEntry(
                element,
                activation: activation,
                sessionIdentity: sessionIdentity,
                source: source,
                sourceWindowFrame: sourceWindowFrame,
                window: window,
                bindingOrigin: bindingOrigin
            )
        }
    }

    private func allocateEntry(
        _ element: AccessibilityElementHandle,
        activation: GridActivation,
        sessionIdentity: SelectionSessionIdentity?,
        source: SelectionSourceIdentity,
        sourceWindowFrame: ScreenRectangle,
        window: AccessibilityElementHandle,
        bindingOrigin: SelectionBindingOrigin
    ) -> SelectionElementIdentity {
        nextIdentity &+= 1
        if nextIdentity == 0 {
            nextIdentity = 1
        }
        let identity = SelectionElementIdentity(rawValue: nextIdentity)
        entries[identity] = Entry(
            activation: activation,
            sessionIdentity: sessionIdentity
                ?? SelectionSessionIdentity(rawValue: identity.rawValue),
            source: source,
            sourceWindowFrame: sourceWindowFrame,
            element: element,
            window: window,
            bindingOrigins: [bindingOrigin],
            mouseBindingLeaseCount: bindingOrigin == .mouseHit ? 1 : 0
        )
        return identity
    }

    private func entry(for identity: SelectionElementIdentity) -> Entry? {
        lock.withLock { entries[identity] }
    }

    private func registryEntry(
        _ entry: Entry,
        matches context: BoundSelectionContext
    ) -> Bool {
        entry.activation == context.activation
            && entry.sessionIdentity == context.sessionIdentity
            && entry.source == context.source
            && entry.sourceWindowFrame == context.sourceWindowFrame
            && entry.bindingOrigins.contains(context.bindingOrigin)
    }

    private func window(
        _ window: AccessibilityElementHandle,
        matches source: SelectionSourceIdentity,
        frame sourceWindowFrame: ScreenRectangle
    ) -> Bool {
        client.setMessagingTimeout(limits.perMessageTimeout, for: window)
        guard client.pid(of: window) == pid_t(source.processIdentifier),
              let frame = client.frame(of: window),
              frame.width >= 0,
              frame.height >= 0
        else {
            return false
        }
        let tolerance = 1.0
        guard abs(frame.minX - sourceWindowFrame.minX) <= tolerance
            && abs(frame.minY - sourceWindowFrame.minY) <= tolerance
            && abs(frame.width - sourceWindowFrame.width) <= tolerance
            && abs(frame.height - sourceWindowFrame.height) <= tolerance
        else {
            return false
        }
        let startUptime = ProcessInfo.processInfo.systemUptime
        guard let windowCount = client.windowCount(
            inProcess: pid_t(source.processIdentifier),
            messagingTimeout: limits.perMessageTimeout
        ),
        windowCount <= limits.maximumWindowsPerProcess,
        let windows = client.windows(
            inProcess: pid_t(source.processIdentifier),
            limit: limits.maximumWindowsPerProcess,
            messagingTimeout: limits.perMessageTimeout
        ),
        windows.count == windowCount
        else {
            return false
        }
        var matchingWindows: [AccessibilityElementHandle] = []
        for candidate in windows {
            guard ProcessInfo.processInfo.systemUptime - startUptime
                    <= limits.totalTimeout else {
                return false
            }
            client.setMessagingTimeout(limits.perMessageTimeout, for: candidate)
            guard let candidateFrame = client.frame(of: candidate) else {
                return false
            }
            if abs(candidateFrame.minX - sourceWindowFrame.minX) <= tolerance
                && abs(candidateFrame.minY - sourceWindowFrame.minY) <= tolerance
                && abs(candidateFrame.width - sourceWindowFrame.width) <= tolerance
                && abs(candidateFrame.height - sourceWindowFrame.height) <= tolerance
            {
                matchingWindows.append(candidate)
            }
        }
        return matchingWindows.count == 1
            && client.isSameElement(matchingWindows[0], window)
    }

    private static func sourceWindowStillMatches(
        _ source: SelectionSourceIdentity,
        _ expected: ScreenRectangle
    ) -> Bool {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionAll],
            kCGNullWindowID
        ) as? [[String: Any]]
        else {
            return false
        }
        let tolerance = 1.0
        let matches = rawWindows.compactMap { window -> UInt32? in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                    == source.processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  abs(frame.minX - expected.minX) <= tolerance,
                  abs(frame.minY - expected.minY) <= tolerance,
                  abs(frame.width - expected.width) <= tolerance,
                  abs(frame.height - expected.height) <= tolerance
            else {
                return nil
            }
            return (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        }
        return matches == [source.windowIdentifier]
    }

    private func display(
        containing grid: TextGridGeometry,
        in displays: [DisplayGeometry]
    ) -> DisplayGeometry? {
        displays.first {
            $0.coreGraphicsBounds.minX <= grid.originX
                && grid.originX < $0.coreGraphicsBounds.maxX
                && $0.coreGraphicsBounds.minY <= grid.originY
                && grid.originY < $0.coreGraphicsBounds.maxY
        }
    }

    private func viewport(
        grid: TextGridGeometry,
        rowCount: Int,
        display: DisplayGeometry
    ) -> GridSelectionViewport? {
        let value = GridSelectionViewport(
            displayID: display.displayID,
            originX: display.appKitFrame.minX
                + (grid.originX - display.coreGraphicsBounds.minX),
            topY: display.appKitFrame.maxY
                - (grid.originY - display.coreGraphicsBounds.minY),
            characterWidth: grid.characterWidth,
            lineHeight: grid.lineHeight,
            visualRowCount: rowCount
        )
        return value.isUsable ? value : nil
    }

    private func caretAnchor(
        location: Int,
        lines: [VisualLine]
    ) -> GridBoundary? {
        for (row, line) in lines.enumerated() {
            guard let start = line.sourceLocation,
                  let length = line.sourceLength
            else {
                continue
            }
            let end = start + length
            if location >= start && location <= end {
                let leadingVisualOffset = max(
                    0,
                    line.text.utf16.count - length
                )
                return GridBoundary(
                    row: row,
                    column: min(
                        leadingVisualOffset + max(0, location - start),
                        line.text.utf16.count
                    )
                )
            }
        }
        return nil
    }

    private func sourceRange(
        for boundary: GridBoundary,
        lines: [VisualLine]
    ) -> Range<Int> {
        guard lines.indices.contains(boundary.row),
              let location = lines[boundary.row].sourceLocation
        else {
            return 0..<0
        }
        guard !lines[boundary.row].text.contains("\t") else {
            return location..<location
        }
        let sourceLength = lines[boundary.row].sourceLength ?? 0
        let leadingVisualOffset = max(
            0,
            lines[boundary.row].text.utf16.count - sourceLength
        )
        let offset = min(
            max(0, boundary.column - leadingVisualOffset),
            sourceLength
        )
        let value = location + offset
        return value..<value
    }
}

extension MacOSAccessibilitySelectionService: MacOSGridMouseAnchorResolving {}
