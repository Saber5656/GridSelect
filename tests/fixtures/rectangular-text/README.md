# Rectangular Text Fixtures

These fixtures support manual QA for the macOS monospace MVP target matrix and
fixture-driven tests for the pure clipboard formatting contract. The test
harness discovers every direct child directory without per-fixture
registration.

Each fixture directory contains:

| File | Purpose |
|---|---|
| `input.txt` or `input.log` | Source text to render in a terminal, editor, browser text area, or log viewer-like pane. |
| `expected.txt` | Expected rectangular text result for the fixture range. |
| `selection.json` | Zero-based, half-open row and column selection metadata. |

Rows and columns are counted over the visible monospace grid. The first row and
first column are `0`. `end` values are exclusive.

Expected files use line-feed separators and no final newline so their bytes
match the clipboard formatting contract. Clipboard pasteboard format details
are owned by issue #10.

## Automated Harness Contract

The canonical tracked fixture root is tests/fixtures/rectangular-text
(lowercase tests).

Tests/GridSelectCoreTests/RectangularTextFixtureTests.swift resolves the
repository from the test source or SwiftPM test executable, so the test does
not depend on the process working directory.

Every direct child directory must:

- contain one selection.json using schemaVersion 1;
- use an id that exactly matches the directory name;
- reference input and expected-output files in the same directory;
- use non-empty, zero-based, half-open row and column ranges;
- keep expected rectangular output within the ASCII monospace MVP; and
- include at least one manual target.

Expected files must not contain carriage returns or a final line feed. Leading,
interior, and trailing spaces inside selected rows remain significant.

To add a fixture, create a new child directory with the three required files
and run swift test. No fixture-specific test switch or registration list needs
to be updated.

| Fixture | Target category | Selected rows | Selected columns | Expected slice |
|---|---|---:|---:|---|
| `terminal-aligned-output` | Terminal | `[2, 6)` | `[6, 24)` | TTY and TIME columns from aligned process output. |
| `log-viewer-syslog` | Log viewer | `[1, 5)` | `[20, 42)` | Level, service, and event columns from fixed-width logs. |
| `editor-fixed-width-table` | Editor | `[0, 5)` | `[17, 24)` | Q2 and Q3 columns from a fixed-width table. |
| `browser-plain-text-area` | Browser plain-text area | `[0, 5)` | `[16, 25)` | Feb and Mar columns from a textarea/pre fixture. |
