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
| Activation | User invokes a global shortcut |
| Selection | User drags a rectangular overlay across visible text |
| Extraction | App maps the rectangle to row and column ranges |
| Output | Selected text is copied to the clipboard |

The MVP succeeds when a user can activate GridSelect, draw a rectangle over
visible monospace text, and copy the corresponding row/column text to the
clipboard without changing the source application.

## Primary Users

- Developers copying columns from terminals, logs, diffs, or command output.
- Operators extracting aligned fields from log viewers or plain-text consoles.
- Writers and analysts copying vertical slices from fixed-width text samples.

## Core Workflows

1. A developer opens a terminal, invokes the global shortcut, drags over a
   rectangular block of command output, and pastes the copied text elsewhere.
2. An operator views aligned logs, selects only the timestamp and status
   columns, and copies the selected rows to an incident note.
3. A user opens a plain-text editor or browser text area, selects a fixed-width
   vertical slice, and copies only the characters inside the rectangle.

## Functional Requirements

| ID | Requirement |
|---|---|
| FR1 | Register a macOS global shortcut that enters rectangular selection mode. |
| FR2 | Display a draggable overlay that lets the user define a rectangle. |
| FR3 | Convert overlay coordinates into text row and column boundaries. |
| FR4 | Preserve row order and column bounds when extracting text. |
| FR5 | Copy the extracted rectangular text to the system clipboard. |
| FR6 | Let the user cancel selection without copying. |

## MVP Assumptions

- Text is visible on screen and belongs to a plain-text or plain-text-like
  monospace region.
- Character width and line height can be treated as stable within the selected
  region.
- Extraction is best effort for MVP and may require user-adjusted rectangle
  placement.
- The app does not need app-specific integrations to complete the MVP.

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
