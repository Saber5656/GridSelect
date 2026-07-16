# ADR 0001: Native macOS Architecture for the MVP

## Status

Accepted. Updated on 2026-07-15 to adopt the maintainer-approved keyboard-first
Grid mode while preserving mouse rectangle selection.

## Context

GridSelect is a pre-alpha OSS utility for rectangular text selection. The first
MVP targets macOS and focuses on monospace or plain text regions in terminal,
editor, browser, and log-viewer style apps.

The repository intentionally has no scaffold yet. This ADR records the initial
architecture direction so that issue #5 can scaffold the project without also
deciding the product architecture.

The MVP needs these capabilities:

- Enter Grid mode by detecting a double-tap of Shift while another app remains
  frontmost.
- Anchor keyboard selection at the frontmost text element's insertion caret and
  adjust it with Shift+Arrow, or anchor mouse selection at the first overlay
  click and adjust it by dragging.
- Show a rectangle overlay above other apps and keep the selected rectangle
  visible after Shift or the mouse button is released.
- Extract text and text bounds from the focused or frontmost app through macOS
  Accessibility APIs where available.
- Map a screen-space rectangle to a row and column range for monospace text.
- Write the extracted rectangular text to the clipboard.
- Provide minimal status and settings for permissions, shortcut configuration,
  and enablement.
- Cover the grid mapping and output rules with automated tests, and cover OS
  integration with focused manual or integration checks.

## Decision

Use a native macOS app written in Swift, with SwiftUI for simple settings/status
surfaces and AppKit/ApplicationServices bridges for system integration.

The initial application shape is a menu-bar utility with no full document
window. AppKit owns the parts where SwiftUI is not the right abstraction: the
narrow Core Graphics event tap, overlay windows, pasteboard integration, and
Accessibility API access. SwiftUI may own the settings and permissions status UI
through a `MenuBarExtra`, settings scene, or AppKit-hosted view, depending on
the scaffold chosen in issue #5.

The implementation should keep platform integration behind narrow service
boundaries so that extraction, grid mapping, and clipboard formatting can be
tested without driving the macOS UI stack.

## Component Boundaries

| Component | Responsibility | MVP approach | Follow-up |
|---|---|---|---|
| Grid activation monitor | Detect double-Shift and protect the activation-to-overlay handoff while another app is frontmost. | Use a narrowly active `CGEventTap`. Normally return all events unchanged and use key-down only as content-blind gesture invalidation. After a recognized second Shift, temporarily consume only Arrow, Command-C, and Escape into a bounded semantic queue until overlay ownership is verified; always pass Shift release and ordinary input through. | Replace the Carbon development shortcut under #12 and expose permission status under #16. |
| Selection coordinator | Own the Grid-mode lifecycle shared by keyboard and mouse. | On double-Shift, create a generation-tagged session bound to the frontmost source; use either caret or first-click anchor, freeze on Shift/mouse release, single-flight copy only on Command-C, and cancel on Escape. Reject stale asynchronous results. | Implementation in #12. |
| Overlay | Render the current caret/rectangle without changing the source app's native selection. | Use transparent AppKit panels. Once Grid mode starts, make the overlay the key responder so Shift+Arrow, Command-C, and Escape are handled locally and do not trigger source-app commands. Retain zero- or nonzero-width frozen state until mouse re-anchor, copy, cancel, or terminal failure. | Validate frozen-state input, spaces/full-screen behavior, and multi-display behavior in #7/#13. |
| Accessibility/text extraction | Find candidate text elements and obtain text, insertion-caret geometry, bounds, and selected range-like metadata. | Use `AXUIElement` APIs through ApplicationServices. Keyboard entry requires resolvable caret geometry; unsupported apps or missing attributes are actionable failures. | Validate concrete attribute availability in #6 and target app matrix in #11/#14. |
| Coordinate-to-grid mapping | Convert keyboard/mouse anchor and focus boundaries into row/column ranges. | Use a VS Code-inspired zero-area caret start: horizontal input moves a half-open column boundary, vertical input spans inclusive endpoint rows like multi-cursors, and mouse points snap to the same boundaries. Normalize screen coordinates and selection direction in a pure Swift model. | Detailed model in #9; implementation/evidence in #12/#13/#14. |
| Clipboard | Publish the rectangular text result. | Use `NSPasteboard.general` and write plain text first. Preserve row order and newline conventions. | Validate output format in #10. |
| Settings/status | Expose Input Monitoring and Accessibility state, Grid input enablement, and copy/failure status. | Keep minimal menu-bar UI. Provide separate, accurate recovery paths for both permissions. | Detailed UI work in #16. |
| Tests | Protect rules that can run without OS permissions. | Unit-test Grid input timing/state transitions, grid mapping, row/column slicing, newline formatting, and error classification. Add manual checks for both permissions, caret/mouse anchors, overlay, and Command-C behavior. | Automated test implementation in #12/#17. |

## Permission and OS Constraints

GridSelect depends on two separately explained macOS permissions:

- Input Monitoring for the normally pass-through active event tap that recognizes
  double-Shift and protects the bounded activation handoff.
- Accessibility for cross-application text, insertion-caret, and geometry
  inspection.

The app must check each permission independently, fail closed when either
required capability is unavailable, and offer the matching System Settings path.

The MVP should avoid screenshot or OCR based extraction, so Screen Recording
permission is not required by this architecture. If a later feature captures
screen pixels, it must be covered by a separate ADR or decision update.

The approved modifier-only double-Shift gesture cannot be represented by Carbon
hot-key registration, so a narrowly active `CGEventTap` is necessary. Outside an
activation handoff, key-down is used only as a content-blind "gesture
interrupted" bit and every event is returned unchanged. Once the second Shift is
recognized, the bounded transition guard may transiently inspect only virtual-key
code and Command-modifier state to classify and consume Arrow,
Command-C, and Escape until the overlay proves key/first-responder ownership;
these become generation-tagged semantic commands, not stored raw events. Shift
release and ordinary input always pass through. When one of those guarded
key-down events is consumed, only its semantic key class is retained briefly so
the matching key-up cannot leak into the source app after overlay handoff. That
matching-release tail expires 500 ms after the consumed key-down, is cleared on
tap disablement, never decodes or stores characters, and passes unrelated or
expired key-up events through unchanged. Timeout, overflow, another key, or
setup failure cancels and discards the pending session. Inspected key/modifier
values are never logged. Listener readiness means that Input Monitoring is
available and the event tap has been installed successfully. The tap remains
enabled while GridSelect is idle so it can detect the next double-Shift, and is
disabled only when permission is unavailable, listener setup fails, macOS
disables it, or teardown is required. Grid-mode commands are handled locally by
the overlay after caret capture. Carbon `Command-Shift-G` remains historical prototype evidence, not a
production fallback or advertised shortcut.

The handoff queue has a fixed capacity of 32 ordered entries. Each guarded
key/repeat semantic consumes one entry. Second-Shift release still passes through
but contributes one semantic `freeze` marker, so replay can distinguish an Arrow
before release from an Arrow after release without retaining raw events. Overflow
cancels before appending the 33rd entry.

Each session uses two immutable contexts. `ActivationSourceContext` is captured
before the overlay takes focus and contains generation, source process, source
window identity/frame, available displays, and an optional focused caret/element
candidate. Exactly once, keyboard caret acceptance or a source-scoped first mouse
click produces `BoundSelectionContext` with the chosen AX element, anchor/range,
and owning display. Copy-time extraction uses only the bound context and fails if
the process, window, element, focus, permission, or generation no longer matches.
Secure text roles/subroles or secure input detected during activation before
overlay presentation must not create an overlay or copy path. If detected after
presentation during final authorization, terminate the session without writing
to the clipboard.

Production logs are allowlisted to coarse event names, permission booleans, and
error classes. They must not contain typed keys, extracted or clipboard text,
process identifiers, bundle/window titles, caret bounds, or selection coordinates.
Explicit diagnostics must be opt-in, redacted, and short-lived.

Clipboard writing is part of the core flow. The MVP writes plain text to the
general pasteboard only after the user presses Command-C while a nonzero-width Grid
selection is frozen. GridSelect does not read clipboard history or replace normal
Command-C behavior outside Grid mode.

Overlay behavior is constrained by macOS spaces, full-screen apps, multiple
displays, Mission Control, and window levels. The overlay must fail gracefully
when it cannot appear above a target surface.

## Pre-alpha Distribution Implications

Because the app needs Accessibility permission and uses system-level UI
integration, pre-alpha builds should be distributed with conservative
expectations:

- Prefer signed and notarized builds once external testers are invited.
- Document that users may need to grant Accessibility permission after each app
  identity change, especially for unsigned or locally rebuilt binaries.
- Keep permission requests explainable and tied to the rectangular-selection
  action.
- Request Input Monitoring only when the user explicitly enables Grid activation
  mode, and explain why it is required. Do not request Screen Recording.
- Treat unsupported target apps as compatibility gaps to track, not as security
  bypasses to work around.

## Alternatives Considered

| Alternative | Pros | Cons | Decision |
|---|---|---|---|
| Swift + SwiftUI/AppKit native macOS | Best fit for Accessibility, overlay windows, pasteboard, signing/notarization, and macOS UX. Small dependency surface for a pre-alpha OSS app. | Requires macOS-specific implementation first and AppKit bridging where SwiftUI is insufficient. | Chosen. |
| Tauri + Rust/TypeScript | Good for cross-platform UI reuse and smaller footprint than Electron. Rust can model extraction logic cleanly. | macOS Accessibility and overlay work still require native bridges. Adds webview/runtime complexity before the first platform is proven. | Defer until cross-platform strategy is revisited. |
| Electron + TypeScript | Fast UI iteration and common contributor stack. | Heavy runtime for a menu-bar utility, awkward native permission/overlay integration, and more distribution surface for a pre-alpha system utility. | Rejected for the MVP. |
| CLI plus helper scripts | Easy to test pure extraction experiments. | Cannot deliver the user-facing double-Shift and overlay workflow. | Useful only for internal spikes, not the app architecture. |
| Carbon global hot key | No Input Monitoring permission and a narrow activation surface. | Cannot express modifier-only double-Shift or observe held Shift/Arrow state; `Command-Shift-G` conflicts with Finder behavior. | Retained only as historical spike evidence; rejected for the approved MVP interaction. |
| OCR/screenshot-first architecture | Could work in apps that expose poor Accessibility text metadata. | Requires Screen Recording, introduces OCR quality problems, and expands privacy concerns beyond the MVP. | Out of scope for MVP. |

## Consequences

The project will start with a macOS-first codebase. That is an intentional
tradeoff: proving the hard OS integration path matters more than abstracting for
Windows and Linux before GridSelect has one usable implementation.

The domain model should still remain portable where practical. Grid mapping,
rectangle normalization, extraction result types, and clipboard text formatting
should not depend on AppKit objects at their public boundary. This gives future
cross-platform work something reusable without weakening the MVP.

The scaffold in issue #5 should create only the minimum structure needed to
express this boundary. It should not introduce OCR, PDF, AI, browser extension,
or cross-platform packages.

## Follow-up Issues

- #5: Scaffold the repository build and project structure.
- #6: Spike macOS Accessibility API text extraction for rectangular regions.
- #7: Spike macOS overlay window behavior for rectangular selection.
- #8: Spike global shortcut and permission flow on macOS.
- #9: Define the coordinate-to-grid mapping model for monospace text.
- #10: Validate clipboard output format for rectangular text.
- #11: Define the MVP target app matrix and manual fixtures.
- #12: Implement the rectangular selection mode lifecycle.
- #16: Add minimal permissions and shortcut settings UI.
- #17: Add automated tests for grid extraction and output formatting.

## References

- GitHub issue [#2](https://github.com/Saber5656/GridSelect/issues/2):
  Record the initial architecture decision for the macOS MVP.
- Apple Developer Documentation:
  [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions),
  [`AXUIElement`](https://developer.apple.com/documentation/applicationservices/axuielement),
  [`NSPanel`](https://developer.apple.com/documentation/appkit/nspanel),
  [`NSPasteboard`](https://developer.apple.com/documentation/AppKit/NSPasteboard),
  [`MenuBarExtra`](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra),
  and [`NSStatusItem`](https://developer.apple.com/documentation/AppKit/NSStatusItem).
