# Using GridSelect

GridSelect is a source-only, pre-alpha macOS MVP. It has no supported packaged,
signed, or notarized application. This guide describes the behavior implemented
in the current source tree.

## Build and Run from Source

| Requirement | Notes |
|---|---|
| macOS 13 or newer | The MVP uses SwiftUI, AppKit, Core Graphics, and macOS Accessibility APIs. |
| Swift 6.0 or newer | Matches the toolchain declared by `Package.swift`. |
| Xcode | Recommended for the standard SwiftPM and XCTest environment; Command Line Tools may be enough to build and run. |

From the repository root:

```sh
swift build
swift run GridSelect
```

The running process adds the GridSelect rectangle icon to the macOS menu bar.
Use that menu to inspect status, open Settings, start or cancel a selection,
recheck permissions, or quit. This development build is not an installable
`.app` bundle.

## Permission Setup

GridSelect reports two independent macOS permission states. Granting one does
not grant or replace the other.

| Permission | Why the MVP needs it |
|---|---|
| Input Monitoring | Runs the narrow global listener that recognizes Double-Shift and protects Arrow, Command-C, or Escape input during the brief handoff to the overlay. |
| Accessibility | Reads the explicitly selected app's insertion caret, visible text, and range geometry, then validates that exact source before copying. |

Screen Recording is not required. GridSelect does not use screenshots or OCR in
the MVP.

### Input Monitoring

1. Start GridSelect and open its menu-bar menu, then choose **Settings…**.
2. Under **Input Monitoring**, choose **Request Input Monitoring Access** or
   **Open Input Monitoring Settings**.
3. In **System Settings > Privacy & Security > Input Monitoring**, enable the
   currently running GridSelect development build.
4. Return to GridSelect and choose **Recheck Input Monitoring** or
   **Recheck Permissions**.
5. Confirm that the menu shows **Active shortcut: Double-Shift** or Settings
   shows the activation gesture without an Input Monitoring warning.

If the status does not update, quit and run `swift run GridSelect` again, then
recheck. A rebuilt local executable may appear to macOS as a changed development
identity; see [Troubleshooting](#troubleshooting).

### Accessibility

1. Open GridSelect Settings from the menu-bar menu.
2. Under **Accessibility**, choose **Request Accessibility Access** or
   **Open Accessibility Settings**.
3. In **System Settings > Privacy & Security > Accessibility**, enable the
   currently running GridSelect development build.
4. Return to GridSelect and choose **Recheck Permissions**. The menu also offers
   **Recheck Accessibility**.
5. Confirm that Accessibility is shown as **Granted** before starting a
   selection.

GridSelect may open Settings automatically when a selection is attempted without
Accessibility access. Input Monitoring can therefore be granted while
Accessibility is still required, or vice versa; complete both sections for the
normal Double-Shift workflow.

## Select with the Keyboard

The keyboard path requires the source app to expose a reliable insertion caret
and stable monospace Accessibility geometry.

1. Bring the source app to the front, show the text without soft wrapping, and
   place its insertion caret at one corner of the intended rectangle.
2. Press and release Shift once, then press Shift again within the macOS system
   double-click interval. Keep the second Shift held.
3. Grid mode starts at the caret as a zero-area selection.
4. While holding Shift, use the Arrow keys:

   | Key | Effect |
   |---|---|
   | Left / Right | Move the focus by one character boundary and change the column width. |
   | Up / Down | Include the adjacent visual row while preserving the current column extent. |

5. Release Shift to freeze the rectangle. Release does not copy or close it.
6. Press Command-C to copy a nonzero-width rectangle as plain text, or Escape to
   cancel without copying.

The anchor remains fixed while the focus crosses it. If the frozen selection is
still a zero-area caret, Command-C does not change the clipboard and GridSelect
asks for at least one selected column.

## Select with the Mouse

Use the mouse path when the target exposes accessible monospace text but does
not expose a reliable insertion caret.

1. Bring the source text to the front and double-tap Shift to enter Grid mode.
2. Click the first character-cell boundary to set the anchor.
3. Drag to the opposite corner. GridSelect snaps both endpoints to the target's
   measured character-cell grid.
4. Release the mouse button to freeze the rectangle. The clipboard is still
   unchanged.
5. Press Command-C to copy, or Escape to cancel.

Both paths keep the source application's native selection unchanged and retain
the overlay until copy, cancel, or a terminal failure.

## Clipboard Output

GridSelect writes one plain-text value. Selected rows remain in source order,
line endings become LF, and no final newline is added. Leading, interior, and
trailing spaces are preserved; short rows are padded with spaces when needed to
keep the selected output rectangular.

The MVP does not write HTML, RTF, CSV, TSV, spreadsheet table data, or other
structured pasteboard types. The full contract is in
[Clipboard Output Format](clipboard-output-format.md).

## Troubleshooting

| Symptom | What to check |
|---|---|
| No menu-bar icon appears | Keep the terminal running and inspect the output from `swift run GridSelect`. This build is a menu-bar process, not a packaged application. |
| **Input Monitoring required** or Double-Shift is inactive | Enable GridSelect in the Input Monitoring pane, return to the app, and choose **Recheck Input Monitoring**. If macOS disabled the listener, rechecking reinstalls it when permission is available. |
| Input Monitoring remains required after a rebuild | Quit GridSelect. If System Settings offers a stale GridSelect entry, remove or disable it, relaunch the current build, grant it again, and recheck. Local source builds do not yet have a stable packaged identity. |
| **Accessibility required** | Enable GridSelect separately in the Accessibility pane and choose **Recheck Permissions**. Input Monitoring alone cannot authorize text or caret reads. |
| Double-Shift does nothing although the shortcut is active | Keep the target app and window frontmost, tap Shift twice within the system double-click interval, and do not press an ordinary key between taps. Use **Start Selection** from the menu to help distinguish gesture trouble from target-text trouble. |
| **Keyboard caret unavailable** appears | The target did not expose usable insertion-caret geometry. Start a new selection and use the first-click mouse path. |
| **Text region unsupported** appears | Use visible, unwrapped monospace text. Tabs with unknown stops, proportional or variable-width content, emoji, combining characters, custom/canvas rendering, or unstable range geometry may be rejected. |
| **Source changed** appears or the overlay cancels | Keep the original app, window, focused text element, and display arrangement unchanged for the session, then start again. Focus loss or a display-configuration change cancels rather than copying stale content. |
| **Secure input is unsupported** appears | Choose a non-secure text region. GridSelect intentionally refuses password and secure-text fields. |
| Command-C leaves the clipboard unchanged | Freeze the rectangle first and select at least one column. Check the GridSelect status for a permission, source, extraction, or pasteboard failure. |
| Selection differs from visible columns | Use a monospace font, disable soft wrapping, keep the region on one display, and retry with ASCII-heavy text. Target-app Accessibility geometry determines the result. |

## Known Limitations

| Area | Current limitation |
|---|---|
| Release and installation | There is no supported binary, `.app` bundle, signing, notarization, or stable TCC permission identity. |
| Platform | macOS 13 or newer only. |
| Shortcut | Double-Shift is fixed and is not configurable in this pre-alpha build. |
| App compatibility | Support is not universal. The target must expose visible text, ranges, bounds, and stable monospace geometry through Accessibility. |
| Keyboard anchoring | Requires a reliable insertion caret. Some otherwise usable targets support only the mouse path. |
| Text model | The live MVP is safest with ASCII-heavy, unwrapped monospace text. Unknown tab stops, proportional or variable-width glyphs, emoji, and combining sequences may be unsupported. |
| Layout and displays | Source or focus changes fail closed. Cross-display selection is not supported; display-configuration changes cancel the session. |
| Output | Plain rectangular text only; no rich text, table semantics, or destination-specific formatting. |
| Excluded content | No secure text, OCR, screenshots, images, PDFs, canvas-only text, or AI processing. |
| Validation | Target-app behavior remains best effort; consult the [MVP target-app matrix](mvp-target-app-matrix.md) for reproducible fixtures and result classifications. |

## Privacy and Security

Outside the recognized startup handoff, GridSelect passes keyboard input through
without decoding or retaining typed characters. During that bounded handoff it
handles only Arrow, Command-C, and Escape as Grid commands; ordinary typed input
passes through and cancels the pending handoff. Once the overlay owns input,
those commands stay within Grid mode.

Accessibility inspection begins only after an explicit selection action and is
bound to the captured source app, window, and text element. A changed source or
secure field fails closed without copying. GridSelect does not require Screen
Recording for the MVP.

Report vulnerabilities using the private process in
[SECURITY.md](../SECURITY.md), never with sensitive source text in a public issue.

## Report a Reproducible Problem

Before opening a normal issue, read [CONTRIBUTING.md](../CONTRIBUTING.md). Include
the macOS version, GridSelect commit, target app and version, keyboard or mouse
path, both permission states, font/wrapping setup, exact status message, and
whether the clipboard changed. The
[manual QA matrix](mvp-target-app-matrix.md) provides fixtures and a fuller
evidence template.

Do not attach real credentials, private logs, confidential clipboard content,
or secure-field samples.

## Request a Feature

Use the [GitHub issue chooser](https://github.com/Saber5656/GridSelect/issues/new/choose)
and select **Feature request**. Explain the rectangular-selection workflow, the
smallest useful change, target app or surface, and relevant permission state.
Keep proposals within the [macOS MVP boundary](product-requirements.md), or use
the [deferred scope tracker](deferred-scope-tracker.md) for post-MVP OCR, PDF,
image, AI, app-specific, structured-output, or cross-platform requests.

Security vulnerabilities and sensitive source text do not belong in feature
requests; use the private process in [SECURITY.md](../SECURITY.md).
