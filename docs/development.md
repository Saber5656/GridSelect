# Development

GridSelect starts as a native macOS Swift package. The first scaffold keeps the
application shell thin and puts testable rules in `GridSelectCore`.

## Requirements

| Tool | Notes |
|---|---|
| macOS 13 or newer | The MVP architecture uses SwiftUI, AppKit, and macOS system APIs. |
| Xcode | Provides the standard SwiftPM and XCTest environment used by CI. |
| Command Line Tools | Enough for `swift build` on some machines, but may not include XCTest for `swift test`. |
| Swift 6.0 or newer | Matches `Package.swift`. |

## Commands

From the repository root:

```sh
swift build
swift test
swift run GridSelect
```

`swift run GridSelect` launches the minimal menu-bar scaffold. It is not yet a
signed `.app` bundle and does not implement global shortcut, overlay,
Accessibility extraction, or clipboard behavior.

Known local limitation: some Command Line Tools-only Swift installations do not
include the XCTest module needed by `swift test`. Use a standard Xcode-selected
developer directory or the GitHub Actions runner for test execution in that
case. Do not add machine-specific framework paths to `Package.swift`.

## Project Layout

| Path | Purpose |
|---|---|
| `Package.swift` | Swift Package Manager manifest for the macOS executable, core library, and tests. |
| `Sources/GridSelect` | Minimal SwiftUI/AppKit executable shell. |
| `Sources/GridSelectCore` | Pure Swift domain and boundary types that can be tested without driving macOS UI. |
| `Tests/GridSelectCoreTests` | Unit tests for core behavior. |
| `.github/workflows/ci.yml` | Pull request CI for `swift build` and `swift test`. |
| `docs/` | Product, architecture, spike, and contributor documentation. |

## Scope Boundaries

This scaffold intentionally leaves the macOS integration work to follow-up
issues:

| Follow-up | Deferred work |
|---|---|
| #12 | Rectangular selection mode lifecycle. |
| #13 | Overlay implementation details after the spike findings are accepted. |
| #14 | Accessibility-backed text extraction. |
| #15 | Clipboard write path. |
| #16 | Permissions and shortcut settings UI. |
| #17 | Broader automated tests for grid extraction and output formatting. |

Do not add OCR, screenshot capture, PDF parsing, browser extensions, AI
dependencies, release automation, or cross-platform packaging to the scaffold
without a new decision record.

## CI

The GitHub Actions workflow runs on `macos-latest` and executes:

```sh
swift build
swift test
```

Keep CI free of secrets and local machine assumptions. Any future signing,
notarization, or release automation should be added in a separate release
workflow after the repository policy is defined.
