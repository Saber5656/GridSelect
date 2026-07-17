# Contributor-Friendly Issue Drafts

Issue: [#20](https://github.com/Saber5656/GridSelect/issues/20)

These reviewed drafts are small entry points for contributors who do not need
deep macOS Accessibility, event-tap, overlay, or permission knowledge. They are
not open work automatically. Before publishing one, a maintainer should verify
that the scope still matches `main`, assign `good first issue`, and add
`help wanted` only when the task is ready for external work.

All fixture text must be synthetic or safely redacted. Do not publish private
logs, credentials, tokens, customer data, or security-sensitive samples.

## Draft 1: Add a One-Column Rectangular-Text Fixture

Suggested labels: `good first issue`, `type:test`

### Goal

Add an ASCII fixture proving that a half-open selection with width one returns
exactly one character from every selected row.

### Scope

- Add `tests/fixtures/rectangular-text/one-column-selection/` with `input.txt`,
  `expected.txt`, and schema-version-1 `selection.json`.
- Add the fixture to the inventory table in the fixture README.
- Use the existing auto-discovery harness; do not add a registration switch.

### Non-goals

- Accessibility, overlay, or application runtime changes.
- Fixture schema changes, Unicode-width policy, or new dependencies.

### Acceptance criteria

- The selected column range has width one and every expected row has one byte.
- The fixture ID matches its directory and all ranges are zero-based and
  half-open.
- The existing fixture suite discovers and passes the new case.

### Validation

```sh
swift test --filter RectangularTextFixtureTests
git diff --check
```

## Draft 2: Add Malformed Fixture Metadata Tests

Suggested labels: `good first issue`, `type:test`

### Goal

Make fixture-authoring failures easier to diagnose without changing the public
fixture schema.

### Scope

- Add focused loader tests for an unsupported schema version, directory/ID
  mismatch, empty range, and missing expected-output file.
- Build cases in a temporary fixture root so tracked fixtures remain unchanged.
- Assert that each error identifies the offending fixture or file.

### Non-goals

- Production selection/runtime changes.
- Schema version 2, a generator, or CI workflow changes.

### Acceptance criteria

- At least four independent invalid cases are covered.
- Each failure is deterministic and actionable.
- The normal tracked fixture suite still passes.

### Validation

```sh
swift test --filter RectangularTextFixtureTests
git diff --check
```

## Draft 3: Add a Copyable Fixture-Authoring Example

Suggested labels: `good first issue`, `documentation`

### Goal

Let a new contributor add a fixture without reverse-engineering existing JSON.

### Scope

- Add a complete schema-version-1 `selection.json` example to the rectangular
  fixture README.
- Explain the directory/ID match, the three required files, significant spaces,
  LF-only expected output, and the no-final-newline rule.
- Add a short author checklist and the focused test command.

### Non-goals

- A fixture generator, schema changes, or workflow automation.
- Changes to production Swift code.

### Acceptance criteria

- The example matches the current `RectangularTextFixture` decoder contract.
- Copying the example into a temporary fixture with matching text is accepted by
  the existing harness.
- Whitespace-significant examples remain visually unambiguous.

### Validation

```sh
swift test --filter RectangularTextFixtureTests
git diff --check
```

## Draft 4: Add an Interior-Blank-Field Fixture

Suggested labels: `good first issue`, `type:test`

### Goal

Prove that spaces inside a selected fixed-width field remain part of rectangular
plain-text output.

### Scope

- Add `tests/fixtures/rectangular-text/blank-fixed-width-field/` with a synthetic
  aligned table containing an empty interior field.
- Select across that field and preserve its interior spaces in `expected.txt`.
- Add one inventory row to the fixture README.

### Non-goals

- A trailing-space policy change, tab expansion, Unicode display width, or AX
  integration.

### Acceptance criteria

- Expected output keeps the interior blank field at the documented width.
- Auto-discovery requires no test registration change.
- Existing and new fixture cases pass together.

### Validation

```sh
swift test --filter RectangularTextFixtureTests
git diff --check
```
