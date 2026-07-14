# GridSelect Product Requirements

## Purpose

GridSelect helps people copy rectangular regions from plain text when normal
linear selection is awkward or lossy. The first version is intentionally narrow:
macOS-first rectangular selection over monospace text, followed by clipboard
copy of the extracted rows and columns.

## MVP Boundary

| Area | MVP requirement |
|---|---|
| Platform | macOS first |
| Source content | Plain-text, monospace regions |
| Activation | User double-taps Shift to enter Grid mode |
| Selection | User defines a rectangle from the current text caret with Shift+Arrow, or from the first overlay click with a mouse drag |
| Extraction | App maps the rectangle to row and column ranges |
| Output | The rectangle remains visible until the user presses Command-C to copy plain text or Escape to cancel |

The MVP succeeds when a user can enter Grid mode over visible monospace text,
define a rectangle with either the keyboard or mouse, inspect the frozen
selection, and press Command-C to copy the corresponding row/column text without
changing the source application's native selection.

## Primary Users

- Developers copying columns from terminals, logs, diffs, or command output.
- Operators extracting aligned fields from log viewers or plain-text consoles.
- Writers and analysts copying vertical slices from fixed-width text samples.

## Core Workflows

1. A developer places the insertion caret in a monospace text file, double-taps
   Shift, and starts from a zero-area caret selection. While the second Shift is
   held, Left/Right changes the width by one character boundary and Up/Down adds
   an adjacent visual row like a column-selection multi-cursor. Releasing Shift
   freezes the selection; Command-C copies it when at least one column is selected.
2. An operator enters Grid mode over aligned logs, clicks the first character of
   a timestamp column, drags a rectangle over the required rows, and releases the
   mouse. The rectangle remains visible until Command-C copies it or Escape
   cancels it.
3. A user switches between keyboard and mouse input for different selections.
   Both paths produce the same frozen rectangle, extraction, plain-text copy,
   success/failure status, and cleanup behavior.

## Functional Requirements

| ID | Requirement |
|---|---|
| FR1 | Detect a double-tap of Shift while another app is frontmost. Outside the recognized startup handoff, do not record, consume, rewrite, or inspect key content; a non-modifier key may only invalidate a pending gesture as a content-blind signal. |
| FR2 | Before the overlay takes keyboard focus, resolve the frontmost text insertion-caret boundary as an immutable zero-area anchor; Left/Right moves the focus column boundary by one cell and Up/Down moves the focus visual row by one while preserving the column extent. |
| FR3 | For mouse selection, snap the first click and current drag point to the same grid boundaries; dragging one character width selects exactly one column and vertical movement spans adjacent visual rows like the keyboard path. |
| FR4 | Keep the selected rectangle visible after Shift or the mouse button is released; do not copy automatically. |
| FR5 | Convert the frozen screen rectangle into text row and column boundaries. |
| FR6 | Preserve row order and column bounds when extracting text. |
| FR7 | Copy the extracted rectangle as plain text when the user presses Command-C in Grid mode. |
| FR8 | Let the user cancel with Escape without copying, and clean up the overlay after cancel, successful copy, or terminal failure. |
| FR9 | Show actionable readiness and failure states for both Input Monitoring and Accessibility permissions. |
| FR10 | After double-Shift is recognized and until the overlay owns keyboard input, transiently classify virtual-key code and Command-modifier state to consume and buffer only Arrow, Command-C, and Escape as bounded semantic Grid commands so immediate input cannot change the source app. Pass Shift release and all ordinary input through unchanged; never decode characters or retain/log the inspected key values. |

Double-Shift means a Shift down/up followed by a second Shift down within the
macOS system double-click interval, with no intervening non-modifier key. The
second Shift may remain held for keyboard adjustment. Releasing it with a caret
anchor freezes the zero-width caret state; a first mouse down may replace that
anchor and start mouse selection. If no caret is available, Grid mode remains
armed for the first mouse click. Shift release by itself neither copies nor exits.

Keyboard and mouse use the same VS Code-inspired column-selection model. The
anchor is an immutable caret/grid boundary and the focus is movable. Column range
is the half-open interval between anchor and focus column boundaries; row range
contains both the anchor and focus visual rows. Crossing the anchor normalizes the
range and continues in the opposite direction. Key repeat applies one boundary
or row step per repeat event. A zero-width selection may display one or more caret
lines, but Command-C does not change the clipboard until at least one column is
selected.

The activation-to-overlay handoff is immediate from the user's perspective. On
the second Shift down, a narrowly active transition guard starts before AX/UI
work is dispatched. Outside this guard, all events pass through. During the
guard, only Arrow, Command-C, and Escape key-down events are consumed and stored
as direction/copy/cancel semantics for the current generation; no characters or
raw event history are retained. Shift modifier changes always pass through so
the source app cannot be left with a stuck modifier, but the second Shift release
is retained as an ordered `freeze` state marker. The fixed queue capacity is 32
entries; every key/repeat semantic and freeze marker consumes one entry, and an
attempted 33rd entry cancels before append. Overlay readiness drains the current
generation in order: Arrow before freeze adjusts the selection, freeze then
freezes it, and Arrow after freeze is consumed but not applied. Any other key,
timeout, overflow, permission failure, or responder failure cancels and discards
the queue without copying.

## MVP Assumptions

- Text is visible on screen and belongs to a plain-text or plain-text-like
  monospace region.
- Keyboard anchoring requires a frontmost text element with a resolvable
  insertion caret. When no reliable caret geometry is available, GridSelect
  reports that keyboard selection is unsupported and leaves the source app
  unchanged; the mouse path remains available.
- Character width and line height can be treated as stable within the selected
  region.
- Extraction is best effort for MVP and may require user-adjusted rectangle
  placement.
- The app does not need app-specific integrations to complete the MVP.
- Input Monitoring is required only for the narrow double-Shift activation
  listener and content-blind intervening-key invalidation. Once Grid mode starts, its overlay handles Arrow, Command-C, and
  Escape locally. Accessibility remains a separate requirement for reading caret
  and text geometry.
- Grid mode binds each selection to the source process and text element captured
  at activation or first mouse click. A source/focus mismatch, stale session, or
  secure text field fails closed without copying.

## Post-MVP Candidates

- Windows and Linux support.
- Variable-width font handling.
- Better calibration for line height, character width, and scroll offsets.
- Optional app-specific improvements after the core model works.
- Structured export formats after raw rectangular copy is dependable.

Advanced input sources and integrations are tracked in the
[deferred scope tracker](deferred-scope-tracker.md). Recording a request there
does not make it an MVP requirement.

## Explicit Non-Goals

| Non-goal | Reason |
|---|---|
| OCR | The MVP is text-first, not image recognition. |
| PDF extraction | PDF layout and text layers add a separate product problem. |
| Screenshot or image handling | GridSelect should not begin as a capture or vision tool. |
| AI summarization | The core value is precise selection and copying. |
| Automatic table structure inference | MVP copies rectangular text, not semantic tables. |
| Full native selection replacement | GridSelect complements existing selection behavior. |
| Word, Excel, Slack, or Notion optimization | App-specific behavior is deferred until the core workflow is proven. |

Use the [deferred scope tracker](deferred-scope-tracker.md) to record examples
or requests for these non-goals without expanding the MVP boundary.

## Verification

- Check the MVP list against issue #1 and confirm it stays focused on
  two-dimensional rectangular text selection.
- Confirm the non-goals do not appear as MVP requirements.
- Confirm the document describes at least three concrete user workflows.
- On macOS, verify both input paths converge on the same frozen-selection state:
  double-Shift -> caret anchor -> Shift+Arrow -> Shift release, and double-Shift
  -> first click -> drag -> mouse release.
- Verify Command-C copies only while Grid mode owns a nonzero-width frozen selection,
  and Escape exits without changing the clipboard.
