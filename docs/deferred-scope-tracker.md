# Deferred Scope Tracker

Issue: [#22](https://github.com/Saber5656/GridSelect/issues/22)
Status: Deferred post-MVP tracker

## Purpose

GridSelect's first useful product is narrow: macOS rectangular selection over
visible monospace text, followed by plain-text clipboard output. This tracker
keeps adjacent ideas visible without letting them become MVP requirements or
block the core text-selection path.

Use this document when a feature request asks GridSelect to read from an image,
PDF, screenshot, rich document, AI model, table structure, specific third-party
app, or another operating system.

## Non-Blocking Rule

Deferred categories are not MVP blockers. A deferred request can be recorded,
linked, and revisited later, but it should not:

- change the MVP boundary in `docs/product-requirements.md`,
- add runtime dependencies to the macOS MVP,
- require Screen Recording, OCR, AI, PDF, or app-specific integrations before
  the plain-text workflow works,
- delay implementation of global shortcut, overlay, extraction, clipboard, or
  permission/status work in the MVP issue set.

## Deferred Categories

| Category | Deferred rationale | Capture guidance | Promotion criteria |
|---|---|---|---|
| OCR and screenshot/image extraction | OCR turns GridSelect into an image-recognition product, adds Screen Recording/privacy concerns, and has different accuracy failure modes from text Accessibility APIs. | Capture source app, screenshot/image type, text density, privacy sensitivity, and why accessible text is unavailable. Do not request or store screenshots in public issues if they may contain private data. | The macOS text MVP is usable; multiple users need image-only text; privacy and permission UX are reviewed; an OCR spike defines accuracy, latency, and failure handling. |
| PDF extraction | PDF text layers, page layout, columns, embedded images, and selection semantics are a separate document-extraction problem. | Capture PDF type, whether it has selectable text, expected rectangle behavior, and whether the request is about text layer extraction or scanned pages. | A separate PDF design proposal exists; text-layer and scanned-PDF paths are split; the proposal does not rely on screenshot fallback as the default. |
| Rich documents and office apps | Word, Pages, Excel, Numbers, and similar apps have native structure, proportional layout, cells, and embedded objects that should not be flattened into MVP monospace assumptions. | Capture app/version, document type, whether native selection already solves the request, and the exact rectangular-copy gap. | The plain-text MVP is stable; one app category has repeated validated requests; a design explains how to preserve or intentionally discard structure. |
| App-specific integrations | Slack, Notion, IDEs, log viewers, terminals, and collaboration apps may expose custom accessibility trees, virtualized rows, or canvas/GPU rendering. Supporting one app can create maintenance obligations. | Capture app/version, target surface, Accessibility capability if known, and whether the request works with the generic monospace path. | The generic path fails for a high-value repeated workflow; the integration has a narrow contract; maintenance and privacy impact are acceptable. |
| AI summarization and transformation | Summarization, cleanup, table inference, and AI transformation change GridSelect from precise copy tooling into content interpretation. | Capture the desired transformation separately from the rectangular selection need. Keep sample text redacted and do not treat AI output as a copy correctness requirement. | Clipboard output is dependable; users explicitly want post-copy transformation; model/provider, privacy, offline/online behavior, and failure modes have a separate design. |
| Table structure inference and structured export | Detecting semantic tables, headers, cells, CSV/TSV, or spreadsheet pasteboard formats is different from copying rectangular plain text. | Capture expected source format, desired output format, and whether plain-text rectangular output is insufficient. | Plain-text rectangular copy works; structured output has clear examples; format decisions are documented separately from the MVP clipboard contract. |
| Cross-platform adjacency | Windows and Linux may matter later, but platform APIs for shortcuts, overlays, permissions, and text extraction differ from macOS. | Capture platform, target apps, comparable OS APIs, and whether the request depends on an MVP-proven GridSelect workflow. Keep detailed feasibility research in issue #21 or its successor. | The macOS MVP is substantially complete; #21 produces a recommendation; shared abstractions are known from real macOS implementation, not speculation. |

## Request Capture Template

Use this template in a GitHub issue comment, follow-up issue, or project note
when a deferred request appears.

| Field | Value |
|---|---|
| Request category |  |
| Source app, document, or platform |  |
| User workflow |  |
| Why MVP text rectangle copy is insufficient |  |
| Example input, redacted if needed |  |
| Expected output or behavior |  |
| Privacy/security sensitivity |  |
| Related MVP issue, if any |  |
| Suggested follow-up | `record only`, `needs spike`, `needs design proposal`, or `reject for MVP` |

## Promotion Gate

A deferred category should become an implementation issue only after all of the
following are true:

1. The current macOS text-selection MVP is useful enough that the request can be
   compared against a working baseline.
2. The request has at least one concrete, reproducible workflow and expected
   output.
3. The feature can be designed without weakening the MVP's privacy story or
   requesting broad permissions silently.
4. The work has its own design proposal, spike, or acceptance criteria.
5. The proposal states what remains out of scope so that it does not become a
   general table extraction, document parsing, OCR, or AI product by accident.

## Current Holding Area

| Request area | Current status | Follow-up owner |
|---|---|---|
| OCR and image/screenshot extraction | Deferred; do not implement in MVP. | Future OCR/privacy spike if demand is proven. |
| PDF extraction | Deferred; do not implement in MVP. | Future PDF text-layer/scanned-PDF design proposal. |
| AI summarization/table inference | Deferred; do not implement in MVP. | Future transformation or structured-output proposal. |
| Word, Excel, Slack, Notion, and similar app-specific work | Deferred; do not prioritize for MVP. | Future app-specific proposal only after generic text path is proven. |
| Windows and Linux | Deferred to issue #21. | Cross-platform research issue. |

## Acceptance Criteria Mapping

| Issue #22 criterion | Evidence |
|---|---|
| A deferred-scope note or tracker exists. | This document is the tracker. |
| Each deferred category has a brief rationale. | The deferred categories table records rationale per category. |
| The README or product requirements can point to this tracker for out-of-scope requests. | README and product requirements link to this document. |
| No deferred category is treated as an MVP blocker. | The non-blocking rule and promotion gate keep all categories outside MVP requirements. |
