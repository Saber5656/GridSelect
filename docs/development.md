# Development

GridSelect is a native macOS Swift package. The application target owns AppKit,
SwiftUI, Core Graphics, Accessibility, and pasteboard adapters, while
`GridSelectCore` keeps selection, geometry, lifecycle, and formatting rules
testable without driving macOS UI.

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

`swift run GridSelect` launches the current menu-bar MVP from source. It includes
the Double-Shift listener, overlay, Accessibility extraction, clipboard path,
and status/settings surface, but it is not a supported, signed, or notarized
`.app` bundle. Development builds may not have a stable macOS permission
identity. Follow [Using GridSelect](usage.md) for the two permission gates and
current interaction.

Known local limitation: some Command Line Tools-only Swift installations do not
include the XCTest module needed by `swift test`. Use a standard Xcode-selected
developer directory or the GitHub Actions runner for test execution in that
case. Do not add machine-specific framework paths to `Package.swift`.

## Project Layout

| Path | Purpose |
|---|---|
| `Package.swift` | Swift Package Manager manifest for the macOS executable, core library, and tests. |
| `Sources/GridSelect` | SwiftUI/AppKit executable plus macOS shortcut, overlay, Accessibility, and pasteboard adapters. |
| `Sources/GridSelectCore` | Pure Swift domain and boundary types for activation, grid selection, lifecycle, formatting, and status. |
| `Tests/GridSelectCoreTests` | Unit, adapter-contract, fixture-loader, and lifecycle tests. |
| `tests/fixtures/rectangular-text` | Auto-discovered rectangular text inputs, selection metadata, and expected plain-text output. |
| `.github/workflows/ci.yml` | Pull request CI for `swift build` and `swift test`. |
| `docs/` | Product, architecture, spike, and contributor documentation. |

## Focused Fixture Checks

The rectangular-text fixture harness discovers every direct child of
`tests/fixtures/rectangular-text`; a new fixture does not need a registration
switch. Follow its [authoring contract](../tests/fixtures/rectangular-text/README.md)
and run:

```sh
swift test --filter RectangularTextFixtureTests
```

The fixture guide defines directory IDs, zero-based half-open ranges, line
endings, significant spaces, and required files. Never add private logs,
credentials, or confidential source text as a public fixture.

## Validation Boundaries

Automated tests cover pure selection rules and many adapter contracts. They do
not replace live macOS checks for event taps, key-window/first-responder
ownership, Input Monitoring and Accessibility transitions, Retina/multi-display
geometry, target-app AX providers, or pasteboard behavior.

Changes to those paths should record the relevant macOS version, target app,
both permission states, expected and actual status, and whether the clipboard or
source app changed. Use the [MVP target-app matrix](mvp-target-app-matrix.md) and
report unavailable manual evidence as pending rather than inferred success.

## Scope Boundaries

Do not add OCR, screenshot capture, PDF parsing, browser extensions, AI
dependencies, release automation, or cross-platform packaging to the project
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
