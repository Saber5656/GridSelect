# MVP Target App Matrix and Manual Fixtures

Issue: [#11](https://github.com/Saber5656/GridSelect/issues/11)

Status: Initial manual QA matrix and reusable fixtures

## Purpose

GridSelect's MVP targets rectangular copying from visible monospace or
plain-text-like regions on macOS. This matrix helps contributors validate the
intended target categories without implying universal app support.

The matrix is manual by design. Automated harness work belongs to issue #17, and
the final clipboard serialization rules belong to issue #10. The fixtures here
only define source text, zero-based rectangular ranges, and plain-text expected
outputs that later tests can reuse.

## Permission And Environment Setup

Run manual checks from a normal macOS GUI session.

| Setup item | Required action | Expected result |
|---|---|---|
| Input Monitoring | Grant Input Monitoring to the stable GridSelect build identity after reading the in-app explanation. Grant Accessibility separately for AX text/caret access; record actual active-filter TCC behavior instead of assuming the two gates are interchangeable. | GridSelect detects double-Shift; during the bounded pre-overlay handoff only Arrow, Command-C, and Escape are held as semantic commands, while ordinary input and Shift release pass through. |
| Accessibility | Grant Accessibility permission to the GridSelect build or the probe host used for validation. | AX reads can inspect text-bearing elements after an explicit selection action. |
| Screen Recording | Do not grant or require it for MVP text extraction. | GridSelect does not use screenshots, OCR, PDF parsing, or image analysis. |
| Grid activation | Double-tap Shift using the production listener. Do not use the historical Command-Shift-G prototype as MVP evidence. | Grid mode enters only for the valid gesture; missing/revoked Input Monitoring remains an explicit blocked state. |
| Font and wrapping | Use a monospace font and disable soft wrapping where the target app allows it. | Visual rows and columns remain stable while selecting. |
| Window layout | Make the text region wide enough to display the fixture without wrapping. | Expected columns are visible in one fixed-width grid. |

If Input Monitoring or Accessibility is unavailable, record the affected path as
`blocked` and include permission evidence instead of treating the target app as
unsupported.

Run the mouse path for every target category: double-Shift, first click at the
fixture anchor, drag to the documented half-open range, release, verify that the
rectangle remains visible and the clipboard is unchanged, then press Command-C.
Run the keyboard caret path at minimum in TextEdit plain-text mode. Record
`unsupportedCaret` separately when a target supports mouse rectangle extraction
but does not expose reliable insertion-caret geometry.

For the activation handoff check, press an Arrow immediately with the second
Shift still held, before the overlay could reasonably finish animating. The
source app's native selection must not move; the direction must appear in the
Grid selection after readiness. Repeat with Escape and Command-C, then verify an
ordinary letter cancels the pending Grid session and still reaches the source app.

## Fixture Convention

Reusable fixtures live under
[`tests/fixtures/rectangular-text/`](../tests/fixtures/rectangular-text/).

Each fixture has:

| File | Meaning |
|---|---|
| `input.txt` or `input.log` | Source text to show in the target app. |
| `expected.txt` | Expected rectangular text result for the fixture's selected range. |
| `selection.json` | Machine-readable fixture metadata and rectangular range. |

`selection.json` uses zero-based, half-open ranges over the visible monospace
grid:

| Field | Meaning |
|---|---|
| `rows.start` | First selected row, inclusive. |
| `rows.end` | First unselected row, exclusive. |
| `columns.start` | First selected column, inclusive. |
| `columns.end` | First unselected column, exclusive. |

Expected output files use `\n` line separators for fixture readability. The
clipboard pasteboard representation is intentionally deferred to issue #10.

## Manual QA Matrix

| Target category | Representative macOS apps/examples | Fixture | Setup | Manual QA steps | Expected observations |
|---|---|---|---|---|---|
| Terminal | Terminal.app primary; iTerm2 optional; Warp tracked separately because GPU/custom rendering may expose different AX metadata. | `terminal-aligned-output` | Open a terminal with a monospace font. Ensure the window is wide enough and the fixture is not wrapped. Run `clear`, then render the fixture with `cat tests/fixtures/rectangular-text/terminal-aligned-output/input.txt` or a full-screen viewer. | Enter Grid mode, mouse-anchor at row 2 / column boundary 6 and drag focus to row 5 / column boundary 24, producing rows `[2, 6)` and columns `[6, 24)`. Release to freeze, then Command-C. Record keyboard caret support separately if the terminal exposes a reliable insertion caret. | A supported terminal exposes visible text, range text, range bounds, and stable line geometry. The frozen selection does not copy early; the pasted result matches the fixture exactly. |
| Log viewer | Console.app for native log-viewer capability observation; Terminal.app running `less` over the fixture as the built-in reproducible log-viewer path; third-party native log viewers optional. | `log-viewer-syslog` | For the reproducible path, run `less tests/fixtures/rectangular-text/log-viewer-syslog/input.log` in Terminal.app with wrapping disabled. For Console.app, open the fixture or equivalent visible monospace log rows if supported. | Mouse-anchor at row 1 / column boundary 20 and drag focus to row 4 / column boundary 42, producing rows `[1, 5)` and columns `[20, 42)`. Freeze, Command-C, and compare with `expected.txt`. Record Console.app capability separately. | The reproducible log-viewer path extracts level, service, and event columns. Native log viewers pass only when their visible rows expose text with usable range geometry. |
| Editor | TextEdit in plain-text mode with a monospace font; CotEditor/BBEdit optional native examples; VS Code/Cursor optional custom/Electron examples. | `editor-fixed-width-table` | Open `tests/fixtures/rectangular-text/editor-fixed-width-table/input.txt` in the editor, use a monospace font, disable soft wrapping, and place the insertion caret at row 0 / column boundary 17. | Keyboard: enter Grid mode, press Right 7 times and Down 4 times while holding the second Shift, producing rows `[0, 5)` / columns `[17, 24)`, then release Shift. Mouse: drag from row 0 / boundary 17 to row 4 / boundary 24. Verify both freeze without copying, then Command-C and compare with `expected.txt`. | TextEdit is the required keyboard-caret evidence target. Both paths must produce the same output without changing native selection. Custom editors may be partial or `unsupportedCaret`; record exact AX attributes. |
| Browser plain-text area | Safari and Chrome showing the local fixture page; `<textarea>` is the primary target and `<pre>` can be observed as a secondary target. | `browser-plain-text-area` | Open `tests/fixtures/rectangular-text/browser-plain-text-area/fixture.html`, click the textarea, keep browser zoom at 100%, and avoid page wrapping. | Mouse-anchor at row 0 / column boundary 16 and drag focus to row 4 / boundary 25, producing rows `[0, 5)` and columns `[16, 25)`. Freeze, Command-C, and compare with `expected.txt`. Repeat keyboard caret selection when reliable; `<pre>` is observational. | Plain browser text areas or `<pre>` content may be supported when the browser exposes useful AX text and bounds. Canvas or virtualized browser content is unsupported for MVP. |

## Result Classification

Use these result values consistently in issue comments, future PR notes, or
manual QA logs:

| Result | Meaning |
|---|---|
| `supported` | The app exposes range text and range geometry, and the pasted output matches the expected fixture. |
| `unsupportedCaret` | Mouse rectangle extraction is supported, but keyboard anchoring is unavailable because reliable insertion-caret geometry is not exposed. |
| `partial` | The app exposes some useful text metadata, but the fixture output is incomplete, shifted, wrapped, or requires a fallback path. |
| `unsupported` | The app does not expose the text/range geometry needed for the MVP, or it uses custom/canvas/image rendering. |
| `blocked` | The run could not reach a capability result because Input Monitoring or Accessibility is missing/revoked, the app is unavailable, or an environment issue prevents the run. |

## Unsupported Or Deferred Categories

These categories are outside the MVP target matrix. Do not expand MVP scope to
handle them while validating issue #11 fixtures.

| Category | MVP status | Reason |
|---|---|---|
| Word, Pages, and rich document editors | Deferred | Rich layout, proportional fonts, embedded objects, and semantic document structure are separate product problems. |
| Excel, Numbers, and spreadsheet grids | Deferred | Native cell selection and structured table semantics should not be conflated with rectangular text copying. |
| Slack, Notion, and app-specific collaboration surfaces | Deferred | Custom rendering, virtualized rows, and rich blocks require app-specific validation after the core model works. |
| PDF viewers such as Preview or Adobe Acrobat | Unsupported for MVP | PDF extraction is explicitly out of scope and should not be replaced by screenshot/OCR behavior. |
| Images, screenshots, OCR, and video frames | Unsupported for MVP | The architecture is text-first and should not request Screen Recording for the MVP path. |
| Canvas/WebGL/GPU-rendered terminals or dashboards | Unsupported unless proven otherwise | Visual monospace text is insufficient; the app must expose accessible text plus range geometry. |
| Secure text fields and password managers | Unsupported | GridSelect must never attempt to bypass secure input protections. |
| Proportional or wrapped rich text | Deferred | MVP assumes stable monospace character width and line height within the selected region. |

### Required secure-text negative check

Use only a dummy password in an OS or test application's secure text field;
never use a password manager record or real credential.

| Action | Expected evidence |
|---|---|
| Record current pasteboard change count/value in a scratch-safe way, focus the dummy secure field, then double-Shift | GridSelect reports a coarse `secure text unsupported` status. No selection overlay, caret/text extraction, or copy session starts. |
| Press Arrow and Command-C after the rejected gesture | GridSelect does not read or log key content, does not write the pasteboard, and does not leave a stale overlay/session. Normal app behavior remains outside Grid mode. |
| Inspect production diagnostics | No PID, bundle/window title, caret/rectangle coordinate, key code/character, secure value, extracted text, or clipboard value is present. |

Permission missing/revoked, listener-disable, responder-loss, display-change, and
copy-failure cleanup remain lifecycle evidence under issues #12/#13/#15/#16 and
must be recorded alongside the target-app results before those issues close.

## Manual QA Evidence Template

Copy this table into an issue comment or task record when a contributor runs a
manual check.

| Field | Value |
|---|---|
| Date |  |
| macOS version |  |
| GridSelect build/probe identity |  |
| Target app and version |  |
| Fixture |  |
| Accessibility trusted |  |
| Input Monitoring granted |  |
| Grid activation listener active |  |
| Font, size, wrapping, zoom |  |
| Selected rows/columns |  |
| Input path (`keyboard` / `mouse`) |  |
| Frozen before Command-C |  |
| Source selection unchanged |  |
| Result classification |  |
| Expected output matched |  |
| AX attributes observed |  |
| Notes/screenshots avoided |  |

## Acceptance Criteria Mapping

| Issue #11 criterion | Evidence in this PR |
|---|---|
| A test matrix document exists in `docs/` or `tests/fixtures/`. | This document defines the target app matrix and manual QA procedure. |
| Fixtures include expected rectangular copy output. | Each fixture directory contains `expected.txt` and `selection.json`. |
| Manual QA steps are clear enough for a new contributor to run. | The matrix lists setup, commands, rows/columns, comparison steps, and expected observations. |
| Unsupported/deferred app categories are listed. | The unsupported/deferred table records out-of-scope app classes and why they are deferred. |
| A contributor can reproduce at least one expected output per target category. | Each target category maps to one fixture with input, selected range, and expected output. |
