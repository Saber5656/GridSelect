# Clipboard Output Format for Rectangular Text

Issue: [#10](https://github.com/Saber5656/GridSelect/issues/10)
Status: Proposed MVP contract

## Scope

This document defines the plain-text clipboard output produced after GridSelect
has mapped an overlay rectangle to text rows and grid columns.

It intentionally does not implement macOS pasteboard writing, automated tests,
target-app fixtures, rich table formats, spreadsheet-specific export, or AI
transformation. Those belong to follow-up implementation and validation issues.

## Coordinate-to-Grid Contract

Clipboard formatting consumes a grid selection that has already been resolved
by the coordinate-to-grid layer:

- `rowRange` is a zero-based, half-open range of existing logical source rows.
- `columnRange` is a zero-based, half-open range of grid cells.
- Rows are already ordered as they appear in the source text, top to bottom.
- Tabs or other variable-width input have already been expanded or rejected by
  the grid-normalization step.

This keeps the clipboard contract compatible with issue #9 without depending
on any unmerged rounding, coordinate-space, or cell-width details. If the
coordinate-to-grid model later changes how a rectangle becomes row and column
bounds, the output rules below still apply to the resulting grid selection.

## Output Rules

| Concern | MVP rule |
|---|---|
| Pasteboard type | Write plain text only. On macOS this means a string/plain-text pasteboard entry such as `NSPasteboard.PasteboardType.string` / `public.utf8-plain-text`. |
| Additional types | Do not write RTF, HTML, CSV, TSV, spreadsheet table data, or app-specific pasteboard types in the MVP. |
| Row order | Emit selected rows in source order. Do not sort, group, or remove rows. |
| Row joining | Join selected row strings with `\n` (LF). |
| Final newline | Do not append a final newline after the last selected row. |
| Source line endings | Treat CRLF, CR, and LF as logical row separators before selection. Output always uses LF. |
| Column slicing | For every selected row, emit exactly `columnRange.count` grid cells. |
| Short lines | If a selected row ends before `columnRange.upperBound`, synthesize ASCII spaces for the missing cells inside the selected rectangle. |
| Missing cells before row end | If `columnRange.lowerBound` is beyond a row's content, emit an all-space row with the selected width. |
| Spaces | Preserve leading, interior, and trailing ASCII spaces. Do not trim output rows. |
| Tabs | Do not emit tabs as delimiters. Source tabs must be expanded to spaces by the grid-normalization step using the coordinate-to-grid tab policy, or the target should be treated as unsupported. |
| Empty selection | A zero-row or zero-column selection should not update the pasteboard. The selection lifecycle should treat it as cancel/no-op. |

The intentional consequence is that clipboard output is rectangular plain text:
each emitted row has the same grid-cell width, even when that produces trailing
spaces. That is more useful for terminal, log, and fixed-width editor workflows
than trimming rows, because trimming would lose the selected column bounds.

## Formatting Algorithm

Given normalized source rows and a non-empty grid selection:

1. Convert source line endings to logical rows.
2. Use the coordinate-to-grid contract to obtain `rowRange` and `columnRange`.
3. For each row in `rowRange`, produce exactly `columnRange.count` cells.
4. Copy existing grid cells that overlap the source row.
5. Fill selected cells beyond the source row with ASCII spaces.
6. Join the formatted rows with LF.
7. Write only that plain text value to the pasteboard.

## Examples

Notation:

- Ranges are zero-based and half-open: `[start, end)`.
- Expected values are shown as escaped strings so that trailing spaces remain
  reviewable without adding trailing whitespace to this Markdown file.
- Visible forms use `.` only to make spaces visible. The dots are not part of
  the clipboard text.

### Example 1: Basic Rectangular Slice

Input text:

```text
0123456789
abcdefghij
KLMNOPQRST
```

Rectangle/range: rows `[0, 3)`, columns `[2, 7)`

Expected clipboard text:

```text
"23456\ncdefg\nMNOPQ"
```

Visible form:

```text
23456
cdefg
MNOPQ
```

### Example 2: Preserve Leading and Trailing Spaces

Input text:

```text
aa  xx  end
bb    y end
cc  zz  end
```

Rectangle/range: rows `[0, 3)`, columns `[4, 8)`

Expected clipboard text:

```text
"xx  \n  y \nzz  "
```

Visible form:

```text
xx..
..y.
zz..
```

### Example 3: Pad Short Lines Inside the Rectangle

Input text:

```text
abcdef
abc
abcdefgh
```

Rectangle/range: rows `[0, 3)`, columns `[2, 7)`

Expected clipboard text:

```text
"cdef \nc    \ncdefg"
```

Visible form:

```text
cdef.
c....
cdefg
```

### Example 4: Normalize Source Line Endings to LF Output

Input text, escaped to show mixed line endings:

```text
"aa11\r\nbb22\rcc33\n"
```

Rectangle/range: rows `[0, 3)`, columns `[2, 4)`

Expected clipboard text:

```text
"11\n22\n33"
```

Visible form:

```text
11
22
33
```

### Example 5: Expand Tabs Before Clipboard Formatting

For this example only, the grid-normalization step uses four-column tab stops
to show the effect. The clipboard output contains spaces, not tab delimiters.

Input text, escaped to show tabs:

```text
"A\tB\tC\nAA\tBB\tCC"
```

Grid-normalized rows:

```text
A...B...C
AA..BB..CC
```

Rectangle/range: rows `[0, 2)`, columns `[4, 9)`

Expected clipboard text:

```text
"B   C\nBB  C"
```

Visible form:

```text
B...C
BB..C
```

### Example 6: Missing Cells Can Produce All-Space Rows

Input text:

```text
left
middle
right
```

Rectangle/range: rows `[0, 3)`, columns `[6, 10)`

Expected clipboard text:

```text
"    \n    \n    "
```

Visible form:

```text
....
....
....
```

## Representative Destination Sanity Plan

These checks validate the plain-text behavior without adding a target app
matrix or fixture files. The target matrix remains issue #11's responsibility.

| Destination | Sample to paste | Expected result | Notes |
|---|---|---|---|
| Plain text editor | Examples 1, 2, and 3 | LF creates separate rows; leading, interior, and trailing spaces remain present when inspected with a visible-whitespace mode or byte view. | TextEdit must be in plain-text mode; code editors should disable auto-trim-on-paste if testing trailing spaces. |
| Terminal | Examples 1 and 3 pasted into a safe capture command such as `cat > /tmp/gridselect-paste.txt` | Captured file bytes match the expected escaped strings, including LF-only row separators and no final newline. | Avoid pasting samples directly at a shell prompt where they could execute commands. |
| Spreadsheet | Examples 1 and 5 | LF creates spreadsheet rows. Because GridSelect does not emit tab delimiters or table pasteboard types, each line remains plain fixed-width text rather than spreadsheet-specific columns. | Spreadsheet-specific splitting/export is explicitly out of scope for the MVP. |
| Browser or issue comment text area | Examples 1 and 4 | Pasted text shows the same row breaks and no extra blank line at the end. | This is a lightweight plain-text web surface check, not a browser extraction fixture. |

Passing this plan means destinations receive a plain-text string with the
documented bytes. It does not imply that every destination preserves visual
trailing spaces in its rendered UI.

## Follow-Up Handoff

| Issue | Handoff |
|---|---|
| [#11](https://github.com/Saber5656/GridSelect/issues/11) | Use the destination sanity plan as input, but keep target-app matrix and fixture files in #11. |
| [#15](https://github.com/Saber5656/GridSelect/issues/15) | Implement pasteboard writing as plain text only, with LF row joining, no final newline, preserved spaces, and no rich/table pasteboard types. |
| [#17](https://github.com/Saber5656/GridSelect/issues/17) | Turn the examples above into unit tests for row joining, short-line padding, trailing spaces, tab expansion, and line-ending normalization. |

## Verification Checklist

- Clipboard output rules are documented.
- At least five examples include input text, rectangle/range, and expected
  clipboard text.
- Representative plain-text destinations have a sanity check plan.
- Follow-up implementation and test issues are linked from this decision.
