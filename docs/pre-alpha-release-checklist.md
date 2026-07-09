# Pre-Alpha Release Checklist

Issue: [#19](https://github.com/Saber5656/GridSelect/issues/19)
Status: Not release-ready

## Purpose

GridSelect must not publish a tag, GitHub Release, public binary, package, or
release automation until the MVP behavior, documentation, tests, manual QA, and
repository safety checks below are complete.

This checklist is the manual gate for the first pre-alpha release. It is
intentionally conservative: passing the checklist means GridSelect is ready for
early technical testers, not that it is production-ready or broadly supported.

## Release Decision

| Question | Current answer |
|---|---|
| Is there a supported release? | No. |
| Is there a public binary/package? | No. |
| Are tags or GitHub Releases allowed now? | No. |
| Is automatic package publishing allowed now? | No. |
| What can be published before this checklist passes? | Documentation and implementation PRs only. |

## Required Gates

Every required gate must be marked `done` before the first pre-alpha tag or
public binary is published.

| Gate | Required evidence | Current status |
|---|---|---|
| MVP behavior | A user can invoke GridSelect, draw a rectangle over visible monospace text, extract the selected rows and columns, and copy plain text to the clipboard without changing the source app. | `blocked` until #12, #13, #14, #15, and #16 are complete. |
| Supported target scope | The supported app categories and unsupported/deferred categories are documented and manually checked against the target app matrix. | `pending`; matrix exists, but implementation evidence is not available yet. |
| Automated tests | CI runs the same relevant test suite that contributors are expected to run locally. Grid mapping, output formatting, and error behavior have unit coverage. | `pending`; scaffold CI exists, broader #17 coverage remains open. |
| Manual QA | Manual QA results are recorded for the MVP target matrix, including permission state, macOS version, target app/version, fixture, expected output match, and result classification. | `pending`; no release candidate QA evidence yet. |
| User documentation | README and usage docs explain current status, installation/build/run steps, Accessibility setup, shortcut behavior, selection/copy flow, troubleshooting, and known limitations. | `pending` until #18 is complete. |
| Security and privacy docs | Security policy, contribution guidance, issue/PR templates, and privacy-sensitive permission explanations are present and current. | `partial`; baseline docs exist, permission-specific usage docs remain pending. |
| Repository hardening | Default branch protection, workflow posture, secret hygiene, security settings, and dependency/code-scanning posture are checked or explicitly deferred with maintainer approval. | `partial`; audit exists, several settings need maintainer confirmation. |
| Packaging decision | Packaging format, bundle identity, versioning, minimum macOS, signing, notarization, entitlements, sandbox stance, and artifact naming are decided and documented. | `blocked`; follow-up decisions required. |
| Release process | Release owner, tag format, release notes, artifact verification, rollback/removal path, and post-release monitoring are documented. | `pending`; no release process document yet. |

## MVP Behavior Gate

The pre-alpha must satisfy the MVP boundary from
[`docs/product-requirements.md`](product-requirements.md):

| Area | Release requirement |
|---|---|
| Activation | A documented global shortcut or explicit pre-alpha equivalent starts selection mode. |
| Selection | The overlay can draw, confirm, cancel, and clean up a rectangular selection. |
| Extraction | Supported monospace text samples produce the documented rectangular text output. |
| Clipboard | Confirmed selections write plain text to the macOS pasteboard using the documented output rules. |
| Errors | Missing permissions, unsupported apps, empty selections, and copy failures are surfaced without crashes or silent incorrect output. |
| Scope control | OCR, screenshots, PDF extraction, AI summarization, and app-specific integrations remain out of scope. |

Blocking MVP issues:

| Issue | Required before release |
|---|---|
| #12 | Selection mode lifecycle is implemented and manually verified. |
| #13 | Draggable overlay interaction is implemented and manually verified. |
| #14 | Monospace text extraction pipeline is implemented with supported/unsupported behavior. |
| #15 | Clipboard copy path is implemented and formatting rules are covered. |
| #16 | Minimal permissions and shortcut status UI exists. |
| #17 | Automated tests cover grid extraction and output formatting. |
| #18 | User-facing README and usage documentation are complete. |

## Documentation Gate

The release candidate must include:

| Document | Requirement |
|---|---|
| `README.md` | States pre-alpha status, no production guarantee, supported MVP path, known limitations, release availability, and links to usage/security/contributor docs. |
| Usage docs | Explain Accessibility permission, shortcut setup, overlay selection, copy behavior, troubleshooting, and how to report reproducible failures. |
| `docs/development.md` | Documents build/test/run commands and local environment caveats. |
| `docs/mvp-target-app-matrix.md` | Lists target categories, fixtures, manual QA steps, result classifications, and unsupported/deferred categories. |
| `SECURITY.md` | Explains vulnerability reporting and supported versions/pre-alpha caveat. |
| `CONTRIBUTING.md` | Explains branch/PR workflow, tests, scope control, and dependency/workflow change expectations. |

## Test And Manual QA Gate

Before release:

| Check | Required evidence |
|---|---|
| CI | All required GitHub Actions checks pass on the release candidate PR. |
| Local build | `swift build` passes on a documented development environment. |
| Local tests | `swift test` passes on an Xcode-backed SwiftPM environment, or the exact environment-only blocker is documented. |
| Grid/output tests | Unit tests cover row/column selection, partial cells, short lines, spaces, line endings, tabs or tab rejection, and output formatting. |
| Manual target matrix | Terminal, editor, browser plain-text area, and log-viewer-like workflows are checked and recorded. |
| Permission states | Accessibility granted, missing, and revoked states are manually exercised. |
| Regression evidence | A maintainer can match selected fixture output against the expected files before tagging. |

Manual QA should use the evidence template in
[`docs/mvp-target-app-matrix.md`](mvp-target-app-matrix.md).

## Repository And Security Gate

Before release, review the repository hardening audit and record any accepted
deferrals:

| Area | Release requirement |
|---|---|
| Branch protection | Default branch remains protected by PR flow, force-push protection, deletion protection, and linear history. |
| Workflow permissions | Actions defaults are reviewed for least privilege before any release workflow is added. |
| Secret hygiene | Current tree and history are scanned with a redacted scanner before release. No publish/deploy secrets are stored unless documented and least-privilege. |
| Security settings | Maintainer confirms Dependabot alerts/security updates, dependency graph, CodeQL posture, Secret Protection, push protection, and private vulnerability reporting posture. |
| Dependencies | Package manifests and lockfiles, if added, are reviewed and covered by CODEOWNERS or an equivalent owner-review rule. |
| Release automation | No workflow publishes packages or binaries until the release process is explicitly approved. |
| Security docs | `SECURITY.md` remains accurate for pre-alpha support and reporting expectations. |

Open hardening items from
[`docs/repository-hardening-audit.md`](repository-hardening-audit.md) must be
closed, confirmed, or explicitly deferred by the maintainer before release.

## Packaging, Signing, And Notarization Questions

These questions must be answered before distributing a binary outside local
developer builds:

| Question | Required decision |
|---|---|
| Package format | Decide whether pre-alpha is a `.app`, zipped `.app`, `.dmg`, Homebrew formula, or source-only milestone. |
| Bundle identity | Choose and keep a stable bundle identifier so macOS permission grants are understandable. |
| Signing | Decide whether Developer ID signing is required for the first external tester build. |
| Notarization | Decide whether every public pre-alpha binary must be notarized and stapled before upload. |
| Hardened runtime | Decide entitlements and hardened runtime settings for Accessibility, hot-key registration, pasteboard, and future sandbox experiments. |
| Sandbox | Decide whether the pre-alpha build is sandboxed, unsandboxed Developer ID, or both. |
| Versioning | Choose initial tag/version format, such as `v0.1.0-alpha.1`, before the first tag. |
| Artifact verification | Decide checksum/SBOM/attestation expectations for uploaded artifacts. |
| TCC reset behavior | Document how testers recover when Accessibility permission is tied to a changed local build identity. |

No key, certificate, secret, or notarization credential should be generated or
stored by an agent. Maintainers perform those steps manually and document only
the non-secret process.

## Explicit Pre-Alpha Non-Guarantees

The first pre-alpha must clearly state that it does not guarantee:

| Non-guarantee | Reason |
|---|---|
| Production readiness | The MVP is for early validation of one narrow macOS workflow. |
| Universal app support | Support depends on target apps exposing useful Accessibility text and geometry. |
| OCR, PDF, image, or screenshot extraction | These are explicit non-goals for the MVP. |
| Rich text or spreadsheet-specific export | The MVP clipboard output is plain text only. |
| Windows or Linux support | Cross-platform work is post-MVP. |
| Stable settings, shortcut, package, or API contracts | Pre-alpha behavior may change as implementation constraints are discovered. |
| A signed/notarized binary | This depends on the packaging decision above. |

## Release Candidate Review

Use this final checklist before tagging:

| Item | Required result |
|---|---|
| All required gates above | `done` or maintainer-approved deferral recorded. |
| Open MVP issues | No open P0/P1 MVP issue blocks the release candidate. |
| PR checks | Required checks pass on the release candidate branch. |
| Review | Code review and required review-thread resolution are complete. |
| Secret scan | Redacted current-tree and history scans are recorded. |
| Manual QA | Target matrix evidence is attached to the release task record. |
| Release notes | Known limitations, non-guarantees, and install/run steps are included. |
| Tag/release action | Performed manually after the release gate is approved. |

## Current Status

GridSelect is **not ready for a pre-alpha release**. The repository may continue
accepting focused implementation, documentation, test, and hardening PRs, but no
tag, GitHub Release, package publishing, or release workflow should be created
until this checklist is satisfied.
