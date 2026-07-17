# Grid Selection Contract Fixtures

This corpus is the data-driven evidence for GridSelect's keyboard and mouse
selection-boundary contract. It is intentionally separate from
`tests/fixtures/rectangular-text`, whose schema only represents completed,
non-empty rectangular text ranges.

The focused Swift test harness discovers every direct lowercase `.json` file in
this directory. It drives the public `GridSelectionLifecycle` and `TextGrid`
APIs; no fixture-specific registration or production behavior is required.

## Schema Version 1

Each fixture contains:

| Field | Rule |
|---|---|
| `schemaVersion` | Must be `1`. |
| `id` | Lowercase kebab-case and exactly equal to the JSON file stem. |
| `description` | Non-empty statement of the behavior under test. |
| `covers` | One or more known acceptance tags. Unknown or duplicate tags are rejected. |
| `equivalenceGroup` | Optional lowercase kebab-case group used to compare keyboard and mouse outcomes. |
| `start.method` | `keyboard` or `mouse`. |
| `start.anchor` | Zero-based, non-negative row and column boundary. |
| `expectedInitial` | Expected lifecycle phase, immutable anchor, focus, normalized row/column ranges, and empty-width flag immediately after binding. |
| `steps` | Ordered `keyboard-move`, `mouse-move`, or `freeze` actions. Every step records the complete expected selection after that action. |
| `output` | Optional source rows and expected plain text used to prove the final half-open range through `TextGrid`. |

Ranges use `{ "start": n, "end": m }` and are always zero-based and
half-open. Row ranges contain both endpoint rows, so they are non-empty. Column
ranges may be empty when anchor and focus are the same boundary.

`keyboard-move` requires `direction` (`left`, `right`, `up`, or `down`) and may
use `repeat` from `1` through `64`. The harness calls the core move API once per
repeat event. `mouse-move` requires a target `boundary` and cannot use
`direction` or `repeat`. `freeze` accepts none of those parameters and must be
the last step.

The accepted `covers` values are:

- `zero-width`
- `one-character-horizontal-move`
- `adjacent-row-multi-cursor-expansion`
- `anchor-crossing`
- `key-repeat`
- `equivalent-mouse-drag`
- `half-open-output-range`

## Extending the Corpus

1. Add one lowercase kebab-case `.json` file directly under this directory.
2. Give it schema version `1` and an `id` matching the file stem.
3. Record the expectation after initial binding and after every action. Keep the
   anchor unchanged and make each expected range agree with anchor/focus.
4. Use a shared `equivalenceGroup` when two fixtures should finish with the
   same selection. An equivalence group must contain both keyboard and mouse
   fixtures.
5. Add `output` only when the final range should also be checked against
   `TextGrid`; selected rows must fully contain the asserted column range.
6. Run the focused fixture tests, the full test suite, and the JSON parse check.

```sh
ruby -rjson -e 'ARGV.each { |path| JSON.parse(File.read(path)) }' \
  tests/fixtures/grid-selection-contract/*.json
swift test --filter GridSelectionContractFixtureTests
swift test
```

The loader rejects symlinks, nested directories, unexpected extensions, unsafe
IDs, unsupported schemas, unknown step/action keys, invalid action parameter
combinations, inconsistent expectations, and fixtures whose declared coverage
is not demonstrated by their data.
