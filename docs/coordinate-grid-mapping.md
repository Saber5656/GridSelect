# Coordinate-to-Grid Mapping Model

Issue: [#9](https://github.com/Saber5656/GridSelect/issues/9)
Status: Proposed contract for the macOS monospace MVP
Scope: Pure coordinate-to-grid model, fixture requirements, and MVP edge-case behavior

## Purpose

GridSelect converts keyboard or mouse column-selection boundaries into a
rectangular range of text rows and columns. For the first MVP, this model is intentionally narrow:
visible monospace text, macOS overlay coordinates, and text geometry exposed by
Accessibility APIs.

This document defines the contract between:

- the AppKit overlay from the issue #7 spike,
- the Accessibility text geometry from the issue #6 spike,
- the pure grid mapper to be implemented in issue #14, and
- the pure unit tests to be added in issue #17.

Clipboard serialization details, pasteboard types, final-newline policy, and
user-visible output formatting belong to issue #10. This model only defines the
selected grid cells and the normalized per-row grid text that a serializer can
consume.

## Inputs and Outputs

### Required Inputs

| Input | Description |
|---|---|
| `SelectionRect` | Overlay rectangle in AppKit global screen points, bottom-left origin, normalized to positive width and height, plus owning display ID. |
| `DisplayGeometry` | The owning display's AppKit frame, Core Graphics bounds, and backing scale used for one boundary conversion. |
| `TextGridGeometry` | Text grid origin, character width, line height, and visual line bounds in canonical top-left screen points. |
| `VisualLine` list | Visible rendered lines in top-to-bottom order, each with text content excluding line terminators and optional source text range metadata. |
| `MappingPolicy` | MVP behavior flags such as tab handling, Unicode-width handling, and unsupported-content classification. |

### Output Shape

The mapper returns either `unsupported`, `empty`, or a `GridSelection`.

| Output field | Meaning |
|---|---|
| `rowStart` | Zero-based visible visual row index, inclusive. |
| `rowEnd` | Zero-based visible visual row index, exclusive. |
| `columnStart` | Zero-based grid column index, inclusive. |
| `columnEnd` | Zero-based grid column index, exclusive. |
| `rows` | One `GridSelectedRow` per selected visual row. |
| `diagnostics` | Non-fatal notes such as clamping, padding, tab expansion, or soft-wrap participation. |

Each `GridSelectedRow` contains:

| Row field | Meaning |
|---|---|
| `visualRowIndex` | Index in the visible visual line list. |
| `sourceRange` | Optional text source range for the selected characters, when it can be represented safely. |
| `gridText` | Selected display cells for this row after MVP normalization. |
| `missingCellCount` | Count of cells synthesized because the requested columns extend past the line's displayed content. |
| `normalizations` | Row-local notes such as `tabExpanded` or `rightPadded`. |

## Coordinate Spaces

All coordinate comparisons must happen in one canonical coordinate space before
grid mapping begins. The MVP canonical space is global top-left-origin screen
points.

| Space | Origin | Unit | Producer | Consumer |
|---|---|---|---|---|
| Overlay view local | View dependent | AppKit points | Overlay view event handling | Overlay only |
| AppKit screen | Bottom-left global screen origin | AppKit points | `window.convertToScreen(_:)` | Boundary normalizer |
| Canonical screen | Top-left global display origin | Screen points | Boundary normalizer | Grid mapper |
| AX range bounds | Top-left global display origin | Screen points after normalization | Accessibility extractor | Boundary normalizer / grid mapper |
| Grid | Text cell origin at row 0, column 0 | Rows and columns | Grid mapper | Extractor / serializer |

The overlay spike defines `SelectionRect.rectInScreenPoints` as AppKit screen
space: global coordinates, bottom-left origin, points. The Accessibility spike
documents that AX range bounds are reported in global top-left-origin geometry.
Legacy references sometimes describe AX bounds as pixels, but the MVP contract
treats all geometry as screen points after a single normalization boundary.

### Single Boundary Conversion

The y-axis flip from AppKit screen space to canonical top-left screen space must
happen exactly once, before the pure grid mapping step. Individual extraction,
grid, or clipboard components must not repeat the flip.

Given:

```text
appRect: SelectionRect.rectInScreenPoints
appFrame: owning NSScreen.frame in AppKit screen space
cgBounds: owning CGDisplayBounds in top-left Core Graphics space
```

Convert the rectangle to canonical top-left points as:

```text
canonical.minX = cgBounds.minX + (appRect.minX - appFrame.minX)
canonical.maxX = cgBounds.minX + (appRect.maxX - appFrame.minX)
canonical.minY = cgBounds.minY + (appFrame.maxY - appRect.maxY)
canonical.maxY = cgBounds.minY + (appFrame.maxY - appRect.minY)
```

The resulting rectangle is standardized so that width and height are positive.

If an AX provider returns backing-pixel-like values for a display where overlay
coordinates are in points, the extractor must convert those AX bounds to screen
points at the same boundary and record the scale assumption in diagnostics.
Fixture validation on a Retina display must prove whether the live target app's
AX bounds match point units or backing units.

### Multi-Display Rules

| Case | MVP behavior |
|---|---|
| Selection starts and ends on one display | Map using that display's `DisplayGeometry`. |
| Drag crosses display boundary | Use the overlay spike behavior: clamp to the starting display before mapping. |
| Text geometry belongs to a different display | Return `unsupportedDisplayMismatch`; do not compare raw rects across spaces. |
| Display removed or geometry changes during selection | Cancel before mapping; do not reuse stale display frames. |
| Negative display coordinates | Supported when both AppKit frame and CG bounds are supplied in `DisplayGeometry`. |

## Text Grid Geometry

### Visual Lines

The mapper operates on visible visual lines, not abstract logical lines.

| Topic | MVP rule |
|---|---|
| Row order | Top-to-bottom order of rendered visual lines. |
| Soft wrapping | Each rendered wrap segment is a separate visual row if AX exposes separate line ranges/bounds. |
| Line terminators | Excluded from `VisualLine.text`; newline serialization is owned by issue #10. |
| Invisible text | Not part of the mapper input. The extractor should pass only visible line geometry. |
| Vertical rows beyond known lines | Not synthesized. Clamp row ranges to measured visible visual rows. |

### Grid Origin

`TextGridGeometry.origin` is the top-left corner of row 0, column 0 in canonical
screen points.

Derivation order:

1. Prefer the common left edge and top edge from AX bounds for the visible line
   ranges.
2. If line bounds have small x jitter, use the minimum x of the accepted line
   bounds and record `lineOriginJitter`.
3. If visible lines do not share a stable left edge, return
   `unsupportedUnstableLineOrigins`.

### Character Width

`characterWidth` is the width of one monospace display cell in screen points.

Derivation order:

1. Prefer direct range bounds for known width-1 character ranges when available.
2. Otherwise divide a non-empty line's range width by its display cell count.
3. Use the median across accepted samples.
4. Reject the target as `unsupportedUnstableCharacterWidth` if accepted samples
   differ by more than the implementation tolerance.

The MVP fixture requirement is deterministic: fixture-provided `characterWidth`
must be explicit, and tests should not depend on live AX metric inference.

### Line Height

`lineHeight` is the height of one visual row in screen points.

Derivation order:

1. Prefer the median distance between consecutive line top edges.
2. If only one line is visible, use that line's bounds height.
3. Reject the target as `unsupportedUnstableLineHeight` if line spacing is not
   stable enough to form a regular grid.

## Row and Column Boundary Rules

Rows and columns are zero-based half-open ranges. Start indexes are inclusive;
end indexes are exclusive.

### VS Code-inspired input boundary model

Both keyboard and mouse input produce the same grid-boundary state before screen
geometry mapping:

| State | Rule |
|---|---|
| Anchor | Immutable insertion/grid boundary `(anchorRow, anchorColumn)` captured at keyboard entry or first mouse down. |
| Initial focus | `(anchorRow, anchorColumn)`, producing a zero-width selection on one row. |
| Left / Right | Move `focusColumn` by exactly one grid boundary per key or repeat event. |
| Up / Down | Move `focusRow` by exactly one visible visual row per key or repeat event without changing `focusColumn`. |
| Rows | `rowStart = min(anchorRow, focusRow)` and `rowEnd = max(anchorRow, focusRow) + 1`; both endpoint rows participate like column-selection multi-cursors. |
| Columns | `columnStart = min(anchorColumn, focusColumn)` and `columnEnd = max(anchorColumn, focusColumn)`; crossing the anchor shrinks to zero and then expands in the opposite direction. |
| Mouse | Convert x to `(x - originX) / characterWidth` and snap to the nearest insertion boundary. For the initial anchor, an exact half-cell tie chooses the trailing/right boundary. After the anchor is immutable, a focus tie chooses the boundary farther from that anchor. Convert y to `floor((topY - y) / lineHeight)` for the endpoint visual row, using the viewport's top anchor and inverted vertical direction. Clamp columns to 0 or greater and rows to visible bounds. Apply a scale-aware epsilon only at exact tested ties. Crossing one character width moves focus by one column. |
| Empty width | `columnStart == columnEnd` is a visible caret/multi-cursor state but has zero text area. Command-C leaves the clipboard unchanged and keeps Grid mode selected with actionable status. |

This follows VS Code's column-selection concept: the cursor starts in one corner,
the opposite corner moves, and each included row has a cursor at the focus edge.
It does not copy whole lines for an empty column selection.

Point-to-boundary fixtures must cover immediately left/right of a midpoint, an
initial-anchor exact midpoint, focus exact midpoints on both sides of the anchor,
exact cell boundaries, negative x clamping, first/last visible row clamping, and
fractional-point Retina geometry.

The rectangle is first intersected with the vertical extent of the known visible
line list. Horizontal selection may extend beyond an individual line's text
length, because missing columns are represented explicitly.

Let:

```text
dxMin = selection.minX - grid.origin.x
dxMax = selection.maxX - grid.origin.x
dyMin = selection.minY - grid.origin.y
dyMax = selection.maxY - grid.origin.y
```

Then:

```text
rowStart = clamp(floor(dyMin / lineHeight), 0, visualLineCount)
rowEnd = clamp(ceil(dyMax / lineHeight), rowStart, visualLineCount)

columnStart = max(0, floor(dxMin / characterWidth))
columnEnd = max(columnStart, ceil(dxMax / characterWidth))
```

If `rowStart == rowEnd` or `columnStart == columnEnd`, the result is `empty`.

### Partial-Cell Behavior

The MVP includes any cell touched by the selection rectangle:

| Rectangle edge | Rule |
|---|---|
| Left/top edge inside a cell | Select that cell using `floor`. |
| Right/bottom edge inside a cell | Include that cell using `ceil`. |
| Right/bottom edge exactly on a cell boundary | Do not include the next cell. |
| Left/top edge before the grid origin | Clamp to row or column 0. |
| Right edge after line content | Keep the requested column range and mark missing cells per row. |

Extraction mapping receives an already snapped boundary rectangle and must not
apply an additional hidden 50 percent inclusion threshold. The midpoint rule
above belongs only to pointer-to-boundary snapping. Implementations should use a
small epsilon only to prevent floating point noise at exact cell boundaries;
fixtures should use exact expected indexes.

## Text-to-Cell Rules

### Supported MVP Content

The supported live MVP content is ASCII-heavy monospace text where every
displayed grapheme in the selected region occupies exactly one grid cell.

| Content | MVP mapping behavior |
|---|---|
| Printable ASCII | Supported as one cell per character. |
| Space | Supported as one cell. Preserve spaces in `gridText`. |
| Empty line | Supported; selected columns are all missing cells. |
| Short line | Supported; pad missing selected cells with spaces and record `rightPadded`. |
| Soft-wrapped visual line | Supported when AX exposes it as a visual line with stable bounds. |

### Tabs

Tabs are not one-cell characters. The mapper must not pretend that `\t` has the
same width as a normal monospace cell.

MVP rule:

- If the extractor or fixture provides a known tab stop, expand tabs into spaces
  in the grid model before slicing and record `tabExpanded`.
- If the tab stop is unknown for live AX input, return `unsupportedTabStopUnknown`.
- The mapper's `gridText` uses expanded spaces. Whether a clipboard serializer
  later preserves tabs, emits spaces, trims padding, or offers an option is
  issue #10's responsibility.

Default fixture tab stop: 8 columns unless the fixture explicitly chooses a
different value.

### Variable-Width Glyphs, Emoji, and Combining Characters

The MVP must avoid corrupting Unicode text by slicing through grapheme clusters
or assuming that every Unicode scalar is one displayed cell.

| Content | MVP behavior |
|---|---|
| Variable-width glyphs in selected rows | Return `unsupportedVariableWidthContent` unless fixture policy explicitly marks the row as pre-normalized. |
| Emoji | Return `unsupportedVariableWidthContent` for live MVP mapping. |
| Combining characters | Return `unsupportedCombiningCharacterContent` if a selected row contains a combining sequence. |
| Grapheme boundary inside selected range | Never split a grapheme. Reject instead of returning partial text. |

Future versions may add Unicode display-width support. That must be a separate
policy because different terminal/editor renderers can disagree about ambiguous
width characters.

### Missing Columns and Padding

The mapping model preserves rectangular geometry.

| Case | MVP behavior |
|---|---|
| Selected columns extend past line length | Append spaces to `gridText` for missing cells and increment `missingCellCount`. |
| Entire selected span is past line length | Return a row of spaces with `missingCellCount == columnEnd - columnStart`. |
| Empty visual line selected | Return a row of spaces for the selected width. |
| Horizontal selection starts after line length | Return spaces for the selected width. |

Serializers may later choose presentation policies, but the mapper must expose
the full rectangular shape so tests can assert the selected geometry.

## Examples

All examples use canonical top-left screen points after the AppKit-to-AX
boundary conversion.

### Example 1: Basic Partial-Cell Inclusion

Input:

```text
origin = (100, 50)
characterWidth = 10
lineHeight = 20
selection = (minX: 120, minY: 52, maxX: 165, maxY: 88)

row 0: "alpha bravo"
row 1: "charlie delta"
row 2: "echo foxtrot"
```

Computed indexes:

```text
rowStart = floor((52 - 50) / 20) = 0
rowEnd = ceil((88 - 50) / 20) = 2
columnStart = floor((120 - 100) / 10) = 2
columnEnd = ceil((165 - 100) / 10) = 7
```

Expected grid rows:

| Visual row | Columns `[2, 7)` | `gridText` |
|---:|---|---|
| 0 | `p h a _ b` | `pha b` |
| 1 | `a r l i e` | `arlie` |

### Example 2: Clamping Left of the Grid

Input:

```text
origin = (50, 100)
characterWidth = 8
lineHeight = 16
selection = (minX: 46, minY: 108, maxX: 66, maxY: 132)

row 0: "HEADER"
row 1: "row one"
row 2: "row two"
```

Computed indexes:

```text
rowStart = 0
rowEnd = 2
columnStart = 0
columnEnd = 2
```

Expected grid rows:

| Visual row | `gridText` | Diagnostics |
|---:|---|---|
| 0 | `HE` | `clampedLeft` |
| 1 | `ro` | `clampedLeft` |

### Example 3: Short Lines and Missing Columns

Input:

```text
origin = (200, 300)
characterWidth = 10
lineHeight = 20
selection = (minX: 220, minY: 300, maxX: 260, maxY: 360)

row 0: "abc"
row 1: "abcdef"
row 2: ""
```

Computed indexes:

```text
rowStart = 0
rowEnd = 3
columnStart = 2
columnEnd = 6
```

Expected grid rows:

| Visual row | Source cells | `gridText` | `missingCellCount` |
|---:|---|---|---:|
| 0 | `c` plus 3 missing cells | `c   ` | 3 |
| 1 | `cdef` | `cdef` | 0 |
| 2 | 4 missing cells | `    ` | 4 |

### Example 4: Known Tab Stop

Input:

```text
origin = (0, 0)
characterWidth = 10
lineHeight = 20
tabStop = 4
selection = (minX: 10, minY: 0, maxX: 50, maxY: 20)

row 0 raw text: "a\tb"
row 0 expanded grid text: "a   b"
```

Computed indexes:

```text
rowStart = 0
rowEnd = 1
columnStart = 1
columnEnd = 5
```

Expected grid rows:

| Visual row | `gridText` | Diagnostics |
|---:|---|---|
| 0 | `   b` | `tabExpanded` |

If the same live target does not provide a known tab stop or calibrated tab
width, the expected result is `unsupportedTabStopUnknown`.

### Example 5: Soft-Wrapped Visual Rows

Input:

```text
origin = (300, 400)
characterWidth = 9
lineHeight = 18
selection = (minX: 318, minY: 418, maxX: 345, maxY: 436)

logical source line: "abcdefghijklmnopqrst"
visual row 0: "abcdefghij"
visual row 1: "klmnopqrst"
```

Computed indexes:

```text
rowStart = 1
rowEnd = 2
columnStart = 2
columnEnd = 5
```

Expected grid rows:

| Visual row | `gridText` | Diagnostics |
|---:|---|---|
| 1 | `mno` | `softWrappedVisualRow` |

The mapper does not reconstruct the original logical line. It selects from the
visual row because the user dragged over rendered screen rows.

### Example 6: AppKit to Canonical Coordinate Conversion

Input:

```text
appFrame = (minX: 0, minY: 0, maxX: 1440, maxY: 900)
cgBounds = (minX: 0, minY: 0, maxX: 1440, maxY: 900)
appRect = (minX: 100, minY: 100, maxX: 300, maxY: 220)
```

Expected canonical rectangle:

```text
canonical.minX = 100
canonical.maxX = 300
canonical.minY = 900 - 220 = 680
canonical.maxY = 900 - 100 = 800
```

This fixture proves that the y-axis flip happens once at the boundary.

## Pure Unit Fixture Requirements

Issue #17 should be able to test this model without AppKit, AX, screen
permissions, or live target applications. A pure fixture should contain only
plain data.

### Fixture Schema Requirements

Each mapping fixture should provide:

| Field | Requirement |
|---|---|
| `name` | Stable fixture name. |
| `displayGeometry` | AppKit frame, CG bounds, backing scale, and display ID. |
| `selectionRect` | AppKit screen-space rectangle from the overlay contract. |
| `expectedCanonicalRect` | Top-left canonical rectangle after boundary conversion. |
| `textGridGeometry` | Origin, character width, line height, and optional tolerance values. |
| `visualLines` | Ordered text rows excluding newline terminators, plus optional source ranges and line bounds. |
| `mappingPolicy` | Tab stop, Unicode-width policy, and unsupported-content policy. |
| `expectedResult` | `GridSelection`, `empty`, or `unsupported` with reason. |
| `expectedDiagnostics` | Expected clamping, padding, tab, wrap, or scale notes. |

### Required Fixture Cases

At minimum, issue #17 should cover:

| Fixture case | Purpose |
|---|---|
| Exact cell boundaries | Right/bottom exact-boundary edges do not include the next cell. |
| Partial cell selection | Any positive overlap includes the touched cell. |
| Left/top clamping | Negative offsets clamp to row/column 0. |
| Selection entirely above or below measured rows | Empty when no measured visual row is touched. |
| Selection entirely left of grid origin | Empty when the rectangle ends before column 0. |
| Short line padding | Missing columns produce spaces and missing-cell counts. |
| Empty selected line | Empty source line returns all missing cells. |
| Known tab stop | Tabs expand before slicing and record diagnostics. |
| Unknown tab stop | Live-style input returns `unsupportedTabStopUnknown`. |
| Variable-width glyph | Returns `unsupportedVariableWidthContent`. |
| Emoji | Returns `unsupportedVariableWidthContent`. |
| Combining sequence | Returns `unsupportedCombiningCharacterContent`. |
| Soft wrap | Visual rows are selected independently from logical lines. |
| Multi-display y flip | Boundary conversion works with non-zero or negative display origins. |
| Retina scale diagnostic | Fixture records whether AX bounds are point-normalized before mapping. |

### Non-Fixture Responsibilities

Issue #11 owns the manual target app matrix and reusable target-app fixture
files. This document only defines what pure grid-mapping unit fixtures must
contain once the code scaffold and test target exist.

## Acceptance Criteria Trace

| Issue #9 criterion | Coverage in this document |
|---|---|
| Coordinate-to-grid mapping model | Inputs, outputs, coordinate spaces, boundary conversion, grid geometry, and index rules. |
| Edge cases with explicit MVP behavior | Tabs, variable-width glyphs, emoji, combining characters, soft wrapping, short lines, and missing columns. |
| Examples with expected output | Six examples with input geometry, computed ranges, and expected rows/results. |
| Test fixture requirements | Pure fixture schema and required fixture cases for issue #17. |

## Follow-Up Handoff

| Issue | Handoff |
|---|---|
| #10 | Decide pasteboard serialization, final newline behavior, trailing padding/trimming policy, and whether tab-expanded grid spaces remain spaces in clipboard output. |
| #11 | Build target app matrix and manual fixtures that can validate AX metric availability, tab stop behavior, Retina units, and soft-wrap exposure. |
| #14 | Implement the boundary normalizer, metric derivation, unsupported-state classification, and pure grid mapper using this contract. |
| #17 | Add pure fixtures for every required case before or alongside live integration checks. |
