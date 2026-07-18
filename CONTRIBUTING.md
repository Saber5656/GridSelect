# Contributing to GridSelect

Thanks for helping make GridSelect useful. The project is pre-alpha, so the best
contributions are small, issue-linked changes that clarify the MVP or reduce
risk around the macOS implementation path.

## Current Project Shape

GridSelect is a native Swift, macOS-first pre-alpha. The source tree implements
the current Double-Shift activation, rectangular overlay, Accessibility-backed
text extraction, plain-text clipboard flow, status UI, and pure core tests. It
does not yet provide a supported, signed, or notarized application release, and
target-app/manual permission validation is still in progress.

Keep changes small and issue-linked. New runtime behavior, dependencies,
workflows, signing, packaging, and release automation require an issue with an
explicitly approved scope.

## Before Opening Work

- Check the existing issues and documentation before proposing a change.
- Keep proposals aligned with the macOS-first rectangular text selection MVP.
- Do not include private notes, local machine details, secrets, tokens, or
  credentials in issues, commits, logs, screenshots, or pull requests.
- Do not report vulnerabilities through normal public issue details. Follow
  [SECURITY.md](SECURITY.md).

## Local Setup and Checks

Use macOS 13 or newer with Swift 6.0 or newer. A full Xcode installation is
recommended because Command Line Tools-only environments may not provide the
same SwiftPM and XCTest setup as CI.

```sh
swift build
swift test
swift run GridSelect
```

See [docs/development.md](docs/development.md) for project layout, focused test
commands, and environment limitations. User interaction and permission setup
are documented in [docs/usage.md](docs/usage.md).

Run the checks that match the change:

| Change | Expected checks |
|---|---|
| Swift source or tests | `swift build`, `swift test`, and `git diff --check` |
| Rectangular-text fixture | `swift test --filter RectangularTextFixtureTests` and the [fixture authoring contract](tests/fixtures/rectangular-text/README.md) |
| Documentation | local link review and `git diff --check` |
| GitHub issue form | parse the edited YAML and inspect the rendered form fields |
| macOS input, overlay, Accessibility, pasteboard, or status behavior | automated checks plus the relevant cases in the [MVP target-app matrix](docs/mvp-target-app-matrix.md); report unperformed manual checks as pending |

## Pull Request Guidelines

1. Create a short-lived branch from the latest `main`.
2. Keep the pull request focused on one issue or one clearly bounded change.
3. Use the pull request template and link the relevant issue.
4. Describe validation that was run. For documentation-only changes, this may be
   Markdown review, link checks, and `git diff --check`.
5. Call out any dependency, workflow, package, signing, release, or permission
   impact explicitly.

Do not report a manual or permission-dependent check as passing unless it was
actually exercised on the stated macOS, target app, and permission state.

## Documentation Guidelines

- Prefer concise docs that explain the current pre-alpha boundary.
- Keep non-goals visible so the MVP does not silently expand.
- Keep user instructions synchronized with the current Double-Shift workflow
  and separate Input Monitoring and Accessibility states.
- Avoid documenting OCR, PDF, image, AI, or cross-platform implementation plans
  as part of the MVP baseline.

## Contributor-Friendly Work

The repository keeps reviewed starter proposals in
[docs/good-first-issue-drafts.md](docs/good-first-issue-drafts.md). These drafts
focus on fixtures, tests, and documentation that do not require deep macOS
Accessibility knowledge. A maintainer should confirm that a draft is still
current before opening it and add `help wanted` only when it is ready for an
external contributor.

## Dependency and Workflow Changes

Changes to package manifests, lockfiles, GitHub Actions workflows, Dependabot
configuration, release files, or CODEOWNERS are maintainer-owned areas. Expect
`@Saber5656` review for those paths.

## Code of Conduct

Participation in this project is covered by the
[Code of Conduct](CODE_OF_CONDUCT.md).
