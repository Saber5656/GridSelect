# ADR 0001: Native macOS Architecture for the MVP

## Status

Proposed for the initial macOS MVP. Maintainer merge of this PR constitutes
acceptance; flip this line to "Accepted" in the next ADR-touching change.

## Context

GridSelect is a pre-alpha OSS utility for rectangular text selection. The first
MVP targets macOS and focuses on monospace or plain text regions in terminal,
editor, browser, and log-viewer style apps.

The repository intentionally has no scaffold yet. This ADR records the initial
architecture direction so that issue #5 can scaffold the project without also
deciding the product architecture.

The MVP needs these capabilities:

- Activate selection mode from a global shortcut.
- Show a temporary rectangle overlay above other apps.
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
window. AppKit owns the parts where SwiftUI is not the right abstraction:
global shortcut registration, overlay windows, pasteboard integration, and
Accessibility API access. SwiftUI may own the settings and permissions status UI
through a `MenuBarExtra`, settings scene, or AppKit-hosted view, depending on
the scaffold chosen in issue #5.

The implementation should keep platform integration behind narrow service
boundaries so that extraction, grid mapping, and clipboard formatting can be
tested without driving the macOS UI stack.

## Component Boundaries

| Component | Responsibility | MVP approach | Follow-up |
|---|---|---|---|
| Shortcut controller | Register and handle the global activation shortcut. | Prefer a native macOS shortcut path that does not require broad keylogging behavior. Avoid event taps unless the shortcut spike proves they are necessary. | Validate API choice, conflicts, and permission behavior in #8. |
| Selection coordinator | Own the selection-mode lifecycle. | Enter on shortcut, display overlay, collect drag rectangle, request extraction, copy result, then exit. | Implementation in #12. |
| Overlay | Render the drag rectangle over the current desktop without stealing normal app focus. | Use an AppKit `NSPanel`/`NSWindow` style overlay with transparent background and explicit event handling. | Validate window level, spaces/full-screen behavior, and multi-display behavior in #7. |
| Accessibility/text extraction | Find candidate text elements and obtain text, bounds, and selected range-like metadata. | Use `AXUIElement` APIs through ApplicationServices. Treat unsupported apps or missing attributes as expected failures, not crashes. | Validate concrete attribute availability in #6 and target app matrix in #11. |
| Coordinate-to-grid mapping | Convert overlay rectangle coordinates into row/column ranges. | Normalize screen coordinates, text element bounds, line metrics, character width, and selection direction into a pure Swift model. Monospace text is the first supported case. | Define detailed model in #9. |
| Clipboard | Publish the rectangular text result. | Use `NSPasteboard.general` and write plain text first. Preserve row order and newline conventions. | Validate output format in #10. |
| Settings/status | Expose permission state, shortcut setting, enable/disable, and version/status. | Keep minimal menu-bar UI. Provide a clear path to macOS Privacy & Security when Accessibility is missing. | Detailed UI work in #16. |
| Tests | Protect rules that can run without OS permissions. | Unit-test grid mapping, row/column slicing, newline formatting, and error classification. Add manual checks for Accessibility, overlay, and global shortcut behavior until scaffolded integration tests exist. | Automated test implementation in #17. |

## Permission and OS Constraints

GridSelect depends on macOS Accessibility trust for cross-application text
inspection. The app should check trust status before extraction and offer the
standard prompt/path to System Settings when trust is missing. Users should
expect to grant Accessibility permission during pre-alpha testing.

The MVP should avoid screenshot or OCR based extraction, so Screen Recording
permission is not required by this architecture. If a later feature captures
screen pixels, it must be covered by a separate ADR or decision update.

The global shortcut implementation must be validated before finalizing the API.
Some native shortcut paths work without Input Monitoring, while lower-level event
taps may trigger broader input monitoring concerns. The MVP should choose the
least invasive option that can reliably activate from other apps.

Clipboard writing is part of the core flow. The MVP only needs to write plain
text to the general pasteboard after an explicit user action. Clipboard reading
or history features are out of scope.

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
- Avoid requesting Screen Recording or Input Monitoring unless a later decision
  proves they are necessary.
- Treat unsupported target apps as compatibility gaps to track, not as security
  bypasses to work around.

## Alternatives Considered

| Alternative | Pros | Cons | Decision |
|---|---|---|---|
| Swift + SwiftUI/AppKit native macOS | Best fit for Accessibility, overlay windows, pasteboard, signing/notarization, and macOS UX. Small dependency surface for a pre-alpha OSS app. | Requires macOS-specific implementation first and AppKit bridging where SwiftUI is insufficient. | Chosen. |
| Tauri + Rust/TypeScript | Good for cross-platform UI reuse and smaller footprint than Electron. Rust can model extraction logic cleanly. | macOS Accessibility and overlay work still require native bridges. Adds webview/runtime complexity before the first platform is proven. | Defer until cross-platform strategy is revisited. |
| Electron + TypeScript | Fast UI iteration and common contributor stack. | Heavy runtime for a menu-bar utility, awkward native permission/overlay integration, and more distribution surface for a pre-alpha system utility. | Rejected for the MVP. |
| CLI plus helper scripts | Easy to test pure extraction experiments. | Cannot deliver the user-facing global shortcut and overlay workflow. | Useful only for internal spikes, not the app architecture. |
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
