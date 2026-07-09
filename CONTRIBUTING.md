# Contributing to GridSelect

Thanks for helping make GridSelect useful. The project is pre-alpha, so the best
contributions are small, issue-linked changes that clarify the MVP or reduce
risk around the macOS implementation path.

## Current Project Shape

GridSelect is currently a documentation-first repository. The app scaffold,
build system, and CI are intentionally separate follow-up work. Please avoid
adding implementation code, workflows, dependency manifests, or release
automation unless an issue explicitly asks for that scope.

## Before Opening Work

- Check the existing issues and documentation before proposing a change.
- Keep proposals aligned with the macOS-first rectangular text selection MVP.
- Do not include private notes, local machine details, secrets, tokens, or
  credentials in issues, commits, logs, screenshots, or pull requests.
- Do not report vulnerabilities through normal public issue details. Follow
  [SECURITY.md](SECURITY.md).

## Pull Request Guidelines

1. Create a short-lived branch from the latest `main`.
2. Keep the pull request focused on one issue or one clearly bounded change.
3. Use the pull request template and link the relevant issue.
4. Describe validation that was run. For documentation-only changes, this may be
   Markdown review, link checks, and `git diff --check`.
5. Call out any dependency, workflow, package, signing, release, or permission
   impact explicitly.

## Documentation Guidelines

- Prefer concise docs that explain the current pre-alpha boundary.
- Keep non-goals visible so the MVP does not silently expand.
- Avoid detailed user guides until an app exists.
- Avoid documenting OCR, PDF, image, AI, or cross-platform implementation plans
  as part of the MVP baseline.

## Dependency and Workflow Changes

Changes to package manifests, lockfiles, GitHub Actions workflows, Dependabot
configuration, release files, or CODEOWNERS are maintainer-owned areas. Expect
`@Saber5656` review for those paths.

## Code of Conduct

Participation in this project is covered by the
[Code of Conduct](CODE_OF_CONDUCT.md).
