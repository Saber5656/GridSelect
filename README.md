# GridSelect

GridSelect is a pre-alpha macOS utility for copying rectangular regions from
visible, monospace plain text. It is intended for columns, aligned fields, logs,
and other fixed-width content where normal linear selection is awkward.

> [!WARNING]
> GridSelect does not have a supported download or release yet. The current MVP
> is run from source and is not packaged, signed, or notarized. Treat it as early
> validation software, not as a production-ready utility.

## Current Status

| Area | Current state |
|---|---|
| Platform | macOS 13 or newer; Windows and Linux are not supported. |
| MVP interaction | The current source includes Double-Shift activation, permission/status UI, a rectangular overlay, keyboard and mouse selection, Accessibility-backed extraction, and plain-text clipboard copy. |
| Target apps | Compatibility is best effort and depends on the source app exposing stable Accessibility text and range geometry. Broad target-app manual QA is not complete. |
| Distribution | Source build only. There is no supported `.app`, package, tag, or GitHub Release. |
| Stability | Pre-alpha behavior, settings, and compatibility may change. |

## MVP Scope

| Area | MVP behavior |
|---|---|
| Source content | Visible, plain-text or plain-text-like monospace regions with stable character-cell geometry |
| Activation | Double-tap Shift while the source app is frontmost |
| Keyboard selection | Start at the zero-area insertion caret; hold the second Shift and use Arrow keys |
| Mouse selection | Use the first overlay click as the anchor, then drag across the character-cell grid |
| Freeze | Release Shift or the mouse button; the rectangle remains visible and is not copied yet |
| Copy or cancel | Press Command-C to copy a nonzero-width rectangle as plain text, or Escape to cancel |

GridSelect is text-first. OCR, screenshots, images, PDF extraction, rich-text
layout, AI processing, structured spreadsheet export, and app-specific
integrations are outside the MVP.

## Build and Run

You need macOS 13 or newer and a Swift 6.0-or-newer toolchain. A full Xcode
installation is recommended for the same SwiftPM and XCTest environment used by
the project.

From the repository root:

```sh
swift build
swift run GridSelect
```

GridSelect appears as a menu-bar item. Before Double-Shift can perform a complete
selection, grant **Input Monitoring** for the activation listener and
**Accessibility** for text and caret geometry. These are independent macOS
permissions; follow the separate setup procedures in the
[usage guide](docs/usage.md#permission-setup).

## Basic Use

1. Focus visible monospace text in another app. For keyboard selection, place
   its insertion caret at one corner of the intended rectangle.
2. Double-tap Shift. Keep the second Shift held for the keyboard path.
3. Use Left/Right to change the width and Up/Down to include adjacent visual
   rows, or click and drag with the mouse.
4. Release Shift or the mouse button to freeze the rectangle.
5. Press Command-C to copy, or Escape to cancel without copying.

A zero-area caret contains no columns, so Command-C leaves the clipboard
unchanged until the selection has nonzero width. See
[Using GridSelect](docs/usage.md) for permission setup, both selection paths,
troubleshooting, privacy behavior, and known limitations.

## Documentation

- [Using GridSelect: build, permissions, selection, and troubleshooting](docs/usage.md)
- [Product requirements and MVP boundary](docs/product-requirements.md)
- [MVP target-app matrix and manual fixtures](docs/mvp-target-app-matrix.md)
- [Clipboard output format](docs/clipboard-output-format.md)
- [Native macOS architecture](docs/adr/0001-macos-native-mvp-architecture.md)
- [Deferred scope tracker](docs/deferred-scope-tracker.md)
- [Pre-alpha release checklist](docs/pre-alpha-release-checklist.md)

## Contributing and Security

Focused, issue-linked contributions are welcome. Read
[CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request, and follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

Do not disclose vulnerabilities or sensitive text in a public issue. Follow the
private reporting guidance in [SECURITY.md](SECURITY.md).

## License

GridSelect is licensed under the [MIT License](LICENSE).
