# Issue Parallel Execution Plan

Date: 2026-07-09 JST
Repository: `Saber5656/GridSelect`

## Purpose

This document identifies which currently open GitHub issues can be executed in
parallel now that there are no open pull requests, and which issues should wait
for shared contracts or earlier validation. The intended output for each
execution item is a focused pull request with small, reviewable commits.

## Source State

| Signal | Current state |
|---|---|
| Open pull requests | None at the start of this assessment. |
| Local base | `main` fast-forwarded to `origin/main` before this document was written. |
| Recently merged prerequisites | Issues #1, #2, #3, #4, #5, #9, #10, and #11 are closed and have merged artifacts on `main`. |
| Open implementation or validation issues | #6, #7, #8, #12, #13, #14, #15, #16, #17, #18, #19, #20, #21, and #22. |

Issue #6, #7, and #8 already have merged spike documentation or prototypes, but
the issues remain open because their acceptance criteria still need live
validation, prototype evidence, or explicit maintainer closure.

## Immediate Parallel Work

These items can be assigned to separate branches immediately. They either touch
different files or can be scoped so that merge conflicts stay unlikely.

| Lane | Issues | PR output | Main files likely touched | Notes |
|---|---|---|---|---|
| A | #8 | Shortcut prototype and validation evidence. | `spikes/macos-shortcut/`, `docs/spikes/macos-global-shortcut-permissions.md` | Builds the missing prototype for the hot-key decision. Independent from overlay and extraction. |
| B | #7 | Overlay prototype validation evidence and small prototype corrections if needed. | `spikes/macos-overlay/`, `docs/spikes/macos-overlay-window.md` | Can run separately from shortcut and Accessibility validation. |
| C | #6 | Accessibility live fixture validation results or a documented blocked result. | `spikes/macos-accessibility/`, `docs/spikes/macos-accessibility-text-extraction.md` | Needs a macOS host with Accessibility permission granted to the probe host. Ask the maintainer if the agent cannot grant that permission. |
| D | #15, partial #17 | Pure clipboard formatting implementation plus unit tests for the rules from #10. | `Sources/GridSelectCore/`, `Tests/GridSelectCoreTests/` | Safe as a partial PR. It should not close #15 until selection-to-copy integration exists. |
| E | #19 | Pre-alpha release checklist. | `docs/pre-alpha-release-checklist.md`, maybe `README.md` | Documentation-only and independent of MVP code. |
| F | #22 | Deferred-scope tracker for OCR, PDF, image, AI, and app-specific integrations. | `docs/deferred-scope-tracker.md`, maybe `README.md` | Post-MVP tracker. Low risk, but lower priority than P0/P1 MVP work. |

Recommended first wave if multiple workers are available:

1. Run lanes A, B, and C in parallel to close the remaining spike uncertainty.
2. Run lane D in parallel only if the worker clearly scopes it as formatter and
   tests, not the full #15 integration acceptance criteria.
3. Run lane E as a small documentation PR when an implementation worker is not
   available.
4. Run lane F only if there is spare capacity; it is useful but explicitly
   post-MVP.

## Conditional Parallel Work

These issues can be split into parallel PRs after one shared interface or
validation decision is made. Starting all of them at once would create avoidable
conflicts in `Sources/GridSelect` and the app lifecycle boundary.

| Issue | Parallelization recommendation | Dependency or coordination gate |
|---|---|---|
| #12 | Start after #7 and #8 have enough validation to define the shortcut-to-selection boundary. It can first land a lifecycle coordinator with mocked overlay, extraction, and clipboard services. | Confirm shortcut trigger result shape and overlay selection result shape. |
| #13 | Start after #7 validation. It can run in parallel with #14 if both consume the existing `SelectionRectangle` boundary and avoid app lifecycle wiring conflicts. | Accept or update the overlay coordinate contract. |
| #14 | Start after #6 has at least one live or explicitly blocked fixture outcome. Pure mapper work may proceed earlier, but live Accessibility integration should not claim broad support. | Confirm AX capability assumptions and rectangle normalization boundary. |
| #15 | Full pasteboard integration should wait for #12 and #14. A pure formatter sub-PR can start now, as lane D. | Selection lifecycle must provide a confirmed rectangular text result. |
| #16 | Start after #8 and the first #12 lifecycle boundary. It should avoid owning overlay and extraction logic. | Status UI needs shortcut registration and Accessibility readiness states. |
| #17 | Broader fixture and CI test coverage can expand after #14 and #15 produce stable public APIs. Fixture-loader tests can begin earlier if coordinated with lane D. | Stable `GridSelectCore` grid, formatter, and error APIs. |
| #18 | README and usage docs should wait for the actual user flow from #12, #13, #15, and #16. Status-only docs can be updated earlier but will not satisfy the issue by themselves. | A user can build or run the MVP path being documented. |
| #20 | Wait until #17 and #18 make contributor setup and good-first-issue candidates concrete. | Contributor docs and fixture/test harness are ready. |
| #21 | Park until the macOS MVP is substantially complete. | Post-MVP platform research gate. |

## Recommended Dependency Waves

| Wave | Goal | Candidate PRs |
|---|---|---|
| 1 | Finish remaining validation and low-conflict foundations. | #8 shortcut prototype, #7 overlay validation, #6 Accessibility validation, #15 formatter sub-PR, #19 checklist, #22 tracker. |
| 2 | Build the user flow behind stable boundaries. | #12 lifecycle coordinator, #13 overlay implementation, #14 Accessibility extraction, #15 pasteboard integration, #16 minimal status UI. |
| 3 | Harden and document the pre-alpha experience. | #17 full fixture/test coverage, #18 user-facing README and usage docs, #20 contributor onboarding issues and fixtures. |
| Parked | Keep non-MVP work visible without blocking the MVP. | #21 cross-platform research, deeper #22 follow-ups. |

## Commit Split Guidance

Each PR should keep commits aligned with reviewable concerns:

| PR type | Suggested commit split |
|---|---|
| Spike validation | `prototype/update`, then `docs/evidence`, then optional `docs/acceptance mapping`. |
| Core implementation | `types/contracts`, then `implementation`, then `tests/fixtures`, then `docs`. |
| UI implementation | `state model`, then `view/controller wiring`, then `manual QA docs`. |
| Documentation-only | `new document`, then `README or index links` if needed. |

Avoid combining unrelated issue lanes in one PR unless a shared interface change
is required. When a single issue is too large for one PR, mark the first PR as a
partial implementation and do not close the issue until all acceptance criteria
are satisfied.

## Human Decisions Needed

| Topic | Needed decision | Impact if unresolved |
|---|---|---|
| Accessibility validation for #6 | Decide whether a human will grant Accessibility permission to the probe host or provide manual run evidence. | #6 can only record `blocked`, and #14 should avoid claiming live app support. |
| Issue closure for #6, #7, #8 | Decide whether merged docs plus follow-up evidence should close the current issues or whether each needs one more validation PR. | Prevents agents from assuming the spike issues are done only because related PRs were merged. |
| Splitting #15 | Approve treating pure clipboard formatting as a partial #15 PR before full lifecycle/extraction integration. | Without approval, #15 should wait for #12 and #14. |

## Verification Performed

| Check | Result |
|---|---|
| Open PR list | `gh pr list --state open` returned an empty list. |
| Open issue list | Reviewed open issues #6, #7, #8, #12, #13, #14, #15, #16, #17, #18, #19, #20, #21, and #22. |
| Local sync | `git fetch origin` then `git merge --ff-only origin/main` updated local `main` to the merged scaffold and documentation state. |
| Build | `swift build` passed locally. |
| Tests | `swift test` failed locally because this Command Line Tools environment cannot import `XCTest`; this matches the documented limitation in `docs/development.md`. |
