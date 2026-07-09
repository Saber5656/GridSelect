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
| Accessibility | Grant Accessibility permission to the GridSelect build or the probe host used for validation. | AX reads can inspect text-bearing elements after an explicit selection action. |
| Screen Recording | Do not grant or require it for MVP text extraction. | GridSelect does not use screenshots, OCR, PDF parsing, or image analysis. |
| Shortcut path | Use the MVP hot-key path when available, or invoke the prototype manually while scaffolding is incomplete. | Selection starts without requiring Input Monitoring for the primary shortcut path. |
| Font and wrapping | Use a monospace font and disable soft wrapping where the target app allows it. | Visual rows and columns remain stable while selecting. |
| Window layout | Make the text region wide enough to display the fixture without wrapping. | Expected columns are visible in one fixed-width grid. |

If Accessibility permission is unavailable, record the target as `blocked` and
include the permission evidence instead of treating the app as unsupported.

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
| Terminal | Terminal.app primary; iTerm2 optional; Warp tracked separately because GPU/custom rendering may expose different AX metadata. | `terminal-aligned-output` | Open a terminal with a monospace font. Ensure the window is wide enough and the fixture is not wrapped. Run `clear`, then render the fixture with `cat tests/fixtures/rectangular-text/terminal-aligned-output/input.txt` or a full-screen viewer. | Activate GridSelect and drag over rows `[2, 6)` and columns `[6, 24)` relative to the first visible fixture content row, not the shell prompt or command row. Paste into a scratch text file and compare with `tests/fixtures/rectangular-text/terminal-aligned-output/expected.txt`. | A supported terminal exposes visible text, range text, range bounds, and stable line geometry. The pasted result matches the fixture exactly. |
| Log viewer | Console.app for native log-viewer capability observation; Terminal.app running `less` over the fixture as the built-in reproducible log-viewer path; third-party native log viewers optional. | `log-viewer-syslog` | For the reproducible path, run `less tests/fixtures/rectangular-text/log-viewer-syslog/input.log` in Terminal.app with wrapping disabled. For Console.app, open the fixture or equivalent visible monospace log rows if supported. | Select rows `[1, 5)` and columns `[20, 42)`, paste into a scratch text file, and compare with `expected.txt`. Record Console.app separately as supported, partial, unsupported, or blocked based on AX capability. | The reproducible log-viewer path extracts level, service, and event columns. Native log viewers pass only when their visible rows expose text with usable range geometry. |
| Editor | TextEdit in plain-text mode with a monospace font; CotEditor/BBEdit optional native examples; VS Code/Cursor optional custom/Electron examples. | `editor-fixed-width-table` | Open `tests/fixtures/rectangular-text/editor-fixed-width-table/input.txt` in the editor, use a monospace font, and disable soft wrapping. | Select rows `[0, 5)` and columns `[17, 24)`, paste into a scratch text file, and compare with `tests/fixtures/rectangular-text/editor-fixed-width-table/expected.txt`. | Native text views are expected to expose AX text roles and range geometry. Custom editors may be partial or unsupported; record exact attributes when available. |
| Browser plain-text area | Safari and Chrome showing the local fixture page; `<textarea>` is the primary target and `<pre>` can be observed as a secondary target. | `browser-plain-text-area` | Open `tests/fixtures/rectangular-text/browser-plain-text-area/fixture.html`, click the textarea, keep browser zoom at 100%, and avoid page wrapping. | Select rows `[0, 5)` and columns `[16, 25)`, paste into a scratch text file, and compare with `expected.txt`. Repeat on `<pre>` only as an observation if time allows. | Plain browser text areas or `<pre>` content may be supported when the browser exposes useful AX text and bounds. Canvas or virtualized browser content is unsupported for MVP. |

## Result Classification

Use these result values consistently in issue comments, future PR notes, or
manual QA logs:

| Result | Meaning |
|---|---|
| `supported` | The app exposes range text and range geometry, and the pasted output matches the expected fixture. |
| `partial` | The app exposes some useful text metadata, but the fixture output is incomplete, shifted, wrapped, or requires a fallback path. |
| `unsupported` | The app does not expose the text/range geometry needed for the MVP, or it uses custom/canvas/image rendering. |
| `blocked` | The run could not reach a capability result because of missing Accessibility permission, unavailable app, or an environment issue. |

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
| Font, size, wrapping, zoom |  |
| Selected rows/columns |  |
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
