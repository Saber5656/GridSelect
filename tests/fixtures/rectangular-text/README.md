# Rectangular Text Fixtures

These fixtures support manual QA for the macOS monospace MVP target matrix.
They are intentionally simple data files, not an automated test harness.

Each fixture directory contains:

| File | Purpose |
|---|---|
| `input.txt` or `input.log` | Source text to render in a terminal, editor, browser text area, or log viewer-like pane. |
| `expected.txt` | Expected rectangular text result for the fixture range. |
| `selection.json` | Zero-based, half-open row and column selection metadata. |

Rows and columns are counted over the visible monospace grid. The first row and
first column are `0`. `end` values are exclusive.

Expected files use line-feed separators for readability. Clipboard pasteboard
format details are owned by issue #10.

| Fixture | Target category | Selected rows | Selected columns | Expected slice |
|---|---|---:|---:|---|
| `terminal-aligned-output` | Terminal | `[2, 6)` | `[6, 24)` | TTY and TIME columns from aligned process output. |
| `log-viewer-syslog` | Log viewer | `[1, 5)` | `[20, 42)` | Level, service, and event columns from fixed-width logs. |
| `editor-fixed-width-table` | Editor | `[0, 5)` | `[17, 24)` | Q2 and Q3 columns from a fixed-width table. |
| `browser-plain-text-area` | Browser plain-text area | `[0, 5)` | `[16, 25)` | Feb and Mar columns from a textarea/pre fixture. |
