#!/usr/bin/env swift

import ApplicationServices
import CoreGraphics
import Foundation

struct Options {
    var rect: CGRect?
    var maxChars = 2_000
    var focusedOnly = false
    var promptPermission = false
    var help = false
}

enum AXProbeResult<Value> {
    case success(Value)
    case failure(AXError)
}

func usage() {
    print("""
    Read-only macOS Accessibility text-region probe.

    Usage:
      swift spikes/macos-accessibility/ax-text-region-probe.swift [--rect=x,y,w,h] [--max-chars=N] [--focused-only] [--prompt-permission]

    Notes:
      - Coordinates are global top-left-origin screen coordinates (Core
        Graphics space), as consumed by AXUIElementCopyElementAtPosition.
      - The probe reports capabilities and small samples only.
      - It does not capture screenshots or mutate native selections.
    """)
}

func parseOptions() -> Options {
    var options = Options()

    for argument in CommandLine.arguments.dropFirst() {
        if argument == "--help" || argument == "-h" {
            options.help = true
        } else if argument == "--focused-only" {
            options.focusedOnly = true
        } else if argument == "--prompt-permission" {
            options.promptPermission = true
        } else if argument.hasPrefix("--max-chars=") {
            let value = String(argument.dropFirst("--max-chars=".count))
            if let parsed = Int(value), parsed > 0 {
                options.maxChars = parsed
            }
        } else if argument.hasPrefix("--rect=") {
            let value = String(argument.dropFirst("--rect=".count))
            let parts = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 4 {
                options.rect = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
            }
        }
    }

    return options
}

func axString(_ value: String) -> CFString {
    value as CFString
}

func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AXProbeResult<CFTypeRef> {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, axString(attribute), &value)
    guard error == .success, let value else {
        return .failure(error)
    }
    return .success(value)
}

func copyParameterizedAttribute(
    _ element: AXUIElement,
    _ attribute: String,
    parameter: CFTypeRef
) -> AXProbeResult<CFTypeRef> {
    var value: CFTypeRef?
    let error = AXUIElementCopyParameterizedAttributeValue(element, axString(attribute), parameter, &value)
    guard error == .success, let value else {
        return .failure(error)
    }
    return .success(value)
}

func attributeNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyAttributeNames(element, &names) == .success,
          let array = names as? [String]
    else {
        return []
    }
    return array.sorted()
}

func parameterizedAttributeNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyParameterizedAttributeNames(element, &names) == .success,
          let array = names as? [String]
    else {
        return []
    }
    return array.sorted()
}

func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    guard case .success(let value) = copyAttribute(element, attribute) else {
        return nil
    }
    return value as? String
}

func intAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
    guard case .success(let value) = copyAttribute(element, attribute) else {
        return nil
    }
    return (value as? NSNumber)?.intValue
}

func rangeFromAXValue(_ value: CFTypeRef) -> CFRange? {
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

func rectFromAXValue(_ value: CFTypeRef) -> CGRect? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgRect else {
        return nil
    }
    var rect = CGRect.zero
    return AXValueGetValue(axValue, .cgRect, &rect) ? rect : nil
}

func axValue(range: CFRange) -> AXValue? {
    var mutableRange = range
    return AXValueCreate(.cfRange, &mutableRange)
}

func visibleRange(_ element: AXUIElement) -> CFRange? {
    guard case .success(let value) = copyAttribute(element, kAXVisibleCharacterRangeAttribute) else {
        return nil
    }
    return rangeFromAXValue(value)
}

func selectedTextRange(_ element: AXUIElement) -> CFRange? {
    guard case .success(let value) = copyAttribute(element, kAXSelectedTextRangeAttribute) else {
        return nil
    }
    return rangeFromAXValue(value)
}

func stringForRange(_ element: AXUIElement, _ range: CFRange) -> AXProbeResult<String> {
    guard let parameter = axValue(range: range) else {
        return .failure(.illegalArgument)
    }

    switch copyParameterizedAttribute(element, kAXStringForRangeParameterizedAttribute, parameter: parameter) {
    case .success(let value):
        if let string = value as? String {
            return .success(string)
        }
        return .failure(.cannotComplete)
    case .failure(let error):
        return .failure(error)
    }
}

func boundsForRange(_ element: AXUIElement, _ range: CFRange) -> AXProbeResult<CGRect> {
    guard let parameter = axValue(range: range) else {
        return .failure(.illegalArgument)
    }

    switch copyParameterizedAttribute(element, kAXBoundsForRangeParameterizedAttribute, parameter: parameter) {
    case .success(let value):
        if let rect = rectFromAXValue(value) {
            return .success(rect)
        }
        return .failure(.cannotComplete)
    case .failure(let error):
        return .failure(error)
    }
}

func lineForIndex(_ element: AXUIElement, _ index: Int) -> Int? {
    let parameter = NSNumber(value: index)
    guard case .success(let value) = copyParameterizedAttribute(
        element,
        kAXLineForIndexParameterizedAttribute,
        parameter: parameter
    ) else {
        return nil
    }
    return (value as? NSNumber)?.intValue
}

func rangeForLine(_ element: AXUIElement, _ line: Int) -> CFRange? {
    let parameter = NSNumber(value: line)
    guard case .success(let value) = copyParameterizedAttribute(
        element,
        kAXRangeForLineParameterizedAttribute,
        parameter: parameter
    ) else {
        return nil
    }
    return rangeFromAXValue(value)
}

func clippedRange(_ range: CFRange, maxLength: Int) -> CFRange {
    CFRange(location: range.location, length: min(range.length, maxLength))
}

func describe(_ element: AXUIElement, label: String, options: Options) {
    let attributes = attributeNames(element)
    let parameterized = parameterizedAttributeNames(element)

    print("## \(label)")
    print("role: \(stringAttribute(element, kAXRoleAttribute) ?? "<unknown>")")
    if let title = stringAttribute(element, kAXTitleAttribute), !title.isEmpty {
        print("title: \(title)")
    }
    print("attributes: \(attributes.joined(separator: ", "))")
    print("parameterizedAttributes: \(parameterized.joined(separator: ", "))")

    if let selected = selectedTextRange(element) {
        print("selectedTextRange: location=\(selected.location) length=\(selected.length)")
    }

    let count = intAttribute(element, kAXNumberOfCharactersAttribute)
    if let count {
        print("numberOfCharacters: \(count)")
    }

    let range: CFRange?
    if let visible = visibleRange(element) {
        print("visibleCharacterRange: location=\(visible.location) length=\(visible.length)")
        range = visible
    } else if let count {
        range = CFRange(location: 0, length: count)
        print("visibleCharacterRange: <missing>; using full range from numberOfCharacters")
    } else {
        range = nil
        print("visibleCharacterRange: <missing>")
    }

    if let range {
        let sampleRange = clippedRange(range, maxLength: options.maxChars)
        switch stringForRange(element, sampleRange) {
        case .success(let sample):
            print("stringForRangeSampleLength: \(sample.count)")
            print("stringForRangeSample:")
            print(sample)
        case .failure(let error):
            print("stringForRangeError: \(error.rawValue) \(error)")
        }

        switch boundsForRange(element, sampleRange) {
        case .success(let rect):
            print("boundsForRangeSample: x=\(rect.origin.x) y=\(rect.origin.y) w=\(rect.width) h=\(rect.height)")
        case .failure(let error):
            print("boundsForRangeError: \(error.rawValue) \(error)")
        }

        if let startLine = lineForIndex(element, range.location) {
            let endIndex = max(range.location, range.location + max(0, range.length - 1))
            let endLine = lineForIndex(element, endIndex) ?? startLine
            print("lineRange: \(startLine)...\(endLine)")
            let lastReportedLine = max(startLine, min(endLine, startLine + 4))
            for line in startLine...lastReportedLine {
                guard let lineRange = rangeForLine(element, line) else {
                    continue
                }
                print("line[\(line)] range: location=\(lineRange.location) length=\(lineRange.length)")
                if case .success(let lineBounds) = boundsForRange(element, clippedRange(lineRange, maxLength: options.maxChars)) {
                    print("line[\(line)] bounds: x=\(lineBounds.origin.x) y=\(lineBounds.origin.y) w=\(lineBounds.width) h=\(lineBounds.height)")
                }
            }
        } else {
            print("lineRange: <unavailable>")
        }
    }

    print("")
}

func main() {
    let options = parseOptions()
    if options.help {
        usage()
        return
    }

    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let trustedOptions = [promptKey: options.promptPermission] as CFDictionary
    let trusted = AXIsProcessTrustedWithOptions(trustedOptions)
    print("accessibilityTrusted: \(trusted)")
    guard trusted else {
        print("Grant Accessibility permission, then run again.")
        Foundation.exit(2)
    }

    let system = AXUIElementCreateSystemWide()
    var candidates: [(String, AXUIElement)] = []

    if case .success(let focusedValue) = copyAttribute(system, kAXFocusedUIElementAttribute),
       CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
        candidates.append(("focused", focusedValue as! AXUIElement))
    }

    if !options.focusedOnly, let rect = options.rect {
        var hitElement: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(system, Float(rect.midX), Float(rect.midY), &hitElement)
        if error == .success, let hitElement {
            candidates.append(("hitTestCenter", hitElement))
        } else {
            print("hitTestCenterError: \(error.rawValue) \(error)")
        }
    }

    var seen: [AXUIElement] = []
    for (label, element) in candidates {
        if seen.contains(where: { CFEqual($0, element) }) {
            continue
        }
        seen.append(element)
        describe(element, label: label, options: options)
    }

    if seen.isEmpty {
        print("No candidate AX elements found.")
        Foundation.exit(3)
    }
}

main()
