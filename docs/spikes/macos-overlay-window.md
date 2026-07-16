# macOS overlay window behavior spike

Issue: https://github.com/Saber5656/GridSelect/issues/7

## Scope

This spike documents an MVP approach for drawing and adjusting a rectangular
selection region above other macOS apps. It intentionally excludes OCR,
screenshot saving, image parsing, and app-specific overlay optimization. It also
does not scaffold the production app, but it includes a minimal standalone
overlay prototype for validating the core window and rectangle behavior.

The goal is to identify the window, input, focus, coordinate, multi-display,
Retina, and permission decisions that should shape the first prototype.

## Recommendation

> [!warning] 2026-07-15 production contract — not yet validated
> Keyboard anchoring, frozen selection, local Command-C, and the permission-aware
> lifecycle below are the approved production design. The prototype and its
> recorded results later in this document cover only the historical mouse-drag
> implementation and are not evidence that these new behaviors pass.

Use one borderless, transparent `NSPanel` per `NSScreen` while the selection
session is active. Configure it as a non-activating panel, keep it above normal
app windows, and draw only the zero- or nonzero-width selection affordance. Keep
it visible after Shift or the mouse button is released; close it on Escape,
successful Command-C copy, or a terminal failure.

Recommended MVP defaults:

| Concern | MVP choice | Reason |
|---|---|---|
| Window class | `NSPanel` subclass | Panels are intended for auxiliary UI, and `.nonactivatingPanel` is panel-oriented. |
| Style mask | `[.borderless, .nonactivatingPanel]` | No title bar or normal window chrome, and showing the panel should not activate GridSelect. |
| Transparency | `isOpaque = false`, `backgroundColor = .clear`, custom `NSView` drawing | The overlay can show the underlying app while still receiving mouse events. |
| Window level | Start with `.statusBar`; test `.floating` and `.screenSaver` as fallbacks | `.floating` may be enough for normal windows. `.statusBar` is a stronger MVP default. `.screenSaver` is very high and should be used only during active selection if required. |
| Spaces/full screen | `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` | Selection should appear in the active Space and above full-screen apps during the session. |
| Mouse handling | Overlay captures mouse events; do not set `ignoresMouseEvents` while selecting | Dragging the rectangle requires the overlay to receive mouse down/drag/up. |
| Keyboard handling | Use the active event-tap transition guard from recognized double-Shift until source/caret capture and overlay key ownership complete; then route commands locally | Only Arrow, Command-C, and Escape are consumed during the bounded handoff; ordinary input and Shift release pass through. |
| Selection output | Store screen-space points and the owning screen/display ID | Pixels are a later screenshot/OCR concern. |

## Apple documentation notes

Primary sources used:

| Topic | Source | Relevant point |
|---|---|---|
| Window levels | [NSWindow.Level](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct) | Window levels are standard macOS stacking levels; stacking by level takes precedence over ordering within a level. |
| Level constants | [NSWindow.Level.statusBar](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct/statusbar), [screenSaver](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct/screensaver), [floating](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct/floating) | Use the least powerful level that satisfies overlay visibility. |
| Non-activating panels | [NSWindow.StyleMask.nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel) | The owning app is not activated by this panel style. |
| Ordering without activation | [NSWindow.orderFrontRegardless()](https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless%28%29) | Moves the window to the front of its level without changing the key or main window. |
| Collection behavior | [NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct) | Use Space and full-screen behaviors deliberately; some behaviors are specific to full screen or Stage Manager. |
| Screen enumeration | [NSScreen](https://developer.apple.com/documentation/appkit/nsscreen), [NSScreen.screens](https://developer.apple.com/documentation/appkit/nsscreen/screens) | `NSScreen` describes available displays; `screens` returns the display list. |
| Coordinate conversion | [High Resolution Guidelines for OS X: APIs for Supporting High Resolution](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/APIs/APIs.html) | Prefer AppKit conversion APIs for screen/backing coordinates instead of doing scale math by hand. |
| Event monitors | [Cocoa Event Handling Guide: Monitoring Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html) | Local monitors see this app's events and can suppress them; global monitors see other apps' events but cannot modify delivery and key events require accessibility trust. |
| Screen capture permission | [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/) | Capturing screen content requires Screen Recording permission; the overlay-only MVP does not capture screen content. |
| Accessibility trust | [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) | Accessibility trust is required by the production flow for source-scoped caret, element, and text geometry access. |

## Overlay/window levels

`NSWindow.Level` is global enough for this use case: a window at a higher level
obscures windows at lower levels, even if the lower-level window is otherwise
frontmost. The MVP should avoid jumping straight to the highest possible level
because an overly aggressive overlay feels like a screenshot or system utility
and can interfere with menus, alerts, and security-sensitive surfaces.

Recommended level test order:

| Level | Expected behavior | MVP decision |
|---|---|---|
| `.floating` | Above normal app windows and common palettes. | Try first in a local prototype, but expect full-screen/Space gaps. |
| `.statusBar` | Higher than normal utility UI and generally suitable for transient status overlays. | Recommended default for issue #7. |
| `.screenSaver` | Very high standard level, intended for screen savers. | Fallback only if `.statusBar` fails over full-screen apps; enable only during active selection and close immediately. |

Avoid raw `CGWindowLevelKey` values for the first MVP unless the AppKit levels
cannot satisfy visibility. AppKit maps these levels to Core Graphics window
level keys, and staying in AppKit keeps the prototype easier to reason about.

## Non-activating transparent panel

The overlay should be visually present but should not make GridSelect feel like
the foreground working app. Use a short-lived non-activating `NSPanel`.

Implementation sketch:

```swift
final class SelectionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

func makeOverlayPanel(for screen: NSScreen) -> SelectionOverlayPanel {
    let panel = SelectionOverlayPanel(
        contentRect: screen.frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false,
        screen: screen
    )

    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = false
    let overlayView = SelectionOverlayView(
        frame: NSRect(origin: .zero, size: screen.frame.size)
    )
    panel.contentView = overlayView
    panel.orderFrontRegardless()
    panel.makeKey()
    panel.makeFirstResponder(overlayView)
    return panel
}
```

Notes:

| Setting | Why it matters |
|---|---|
| `canBecomeKey` | Borderless panels need an explicit key-window strategy for Command-C/Escape handling. |
| `canBecomeMain = false` | The overlay is a transient tool, not the document/main surface. |
| `orderFrontRegardless()` | Shows the overlay without activating GridSelect or changing main/key windows by itself; pair it with `makeKey()`, `makeFirstResponder(_:)`, and verified local Command-C/Escape routing. |
| `ignoresMouseEvents = false` | Required on the owning panel throughout `armed`, adjustment, drag, and frozen `selected` states. Making it click-through is a terminal cancel that must run cleanup at the same time. Nonowning display panels remain visually passive but must not become alternate key responders. |

After `makeKey()` and `makeFirstResponder(overlayView)`, the session verifies
`panel.isKeyWindow` and identity of the actual first responder. If either check
fails, it returns no selection and closes every panel through terminal cleanup.

## Input handling

The MVP should keep input local to the overlay while it is visible.

State machine:

| State | Event | Action |
|---|---|---|
| `dragging` | Mouse dragged | Normalize anchor/current point into a rectangle and redraw. |
| `inactive` | Valid double-Shift and permissions revalidated | Create a generation-tagged `armed` session bound to the captured source process; attempt a caret snapshot before showing the overlay. |
| `armed` | Caret snapshot is supported and second Shift remains held | Record the caret boundary as immutable anchor, initialize focus at the same boundary (zero area), and enter `keyboardAdjusting`. |
| `armed` | Caret snapshot is unsupported but source is otherwise eligible | Disable keyboard adjustment for this session, show actionable status, and keep first-click mouse selection available. |
| `armed` | First mouse down validates against the captured source window/geometry, click location, and a source-scoped AX hit test | Bind the hit AX element/display, record the click anchor, and enter `dragging`; otherwise remain armed. |
| `keyboardAdjusting` | Left/Right while second Shift is held | Move the focus column boundary by one cell per event/repeat and redraw every included row. |
| `keyboardAdjusting` | Up/Down while second Shift is held | Move the focus visual row by one while preserving the focus column, adding/removing an adjacent row cursor. |
| `keyboardAdjusting` | Second Shift released | Freeze the current zero- or nonzero-width selection; do not copy. |
| `dragging` | Mouse up | Freeze the snapped zero- or nonzero-width selection; do not copy. |
| `selected` | Command-C with zero width | Consume the Grid command, leave the clipboard unchanged, retain the selection, and show “Select at least one column.” |
| `selected` with zero width | First mouse down | Replace the caret anchor with the snapped mouse boundary and enter `dragging`. |
| `selected` | First Command-C with nonzero width | Atomically enter `copying` with an immutable source/rectangle snapshot and generation; consume repeated Command-C. |
| `copying` | Current-generation extraction/copy result | Publish only the current session result, report status, and run terminal cleanup. Discard stale or canceled completions without writing. |
| Any active state | Escape | Cancel, close panels, return no selection. |
| Any active state | Overlay loses key/first-responder ownership, source identity changes, permission fails, or listener is disabled | Fail closed through the same idempotent cleanup path without copying. |
| Any active state | Display configuration change | Treat the MVP session as terminal: cancel and clean up every panel without reusing the previous rectangle. |

Keyboard and mouse differ only in how they establish and adjust the anchor. Both
paths converge on the same persistent `selected` state. Input release freezes
the rectangle, and only Command-C requests extraction/copy.

Avoid global mouse monitors for rectangle dragging. If the panel covers each
screen and accepts mouse events, mouse down/drag/up are local overlay events.
Global monitors add complexity, cannot prevent normal event delivery, and move
the design toward accessibility/input-monitoring permission questions.

Keyboard handling options:

| Option | Permission profile | Tradeoff |
|---|---|---|
| `keyDown` on the overlay view/panel | No extra permission | Works if the panel is key during selection. |
| Local `NSEvent` monitor | No extra permission | Useful for Command-C/Escape while the app is dispatching overlay events. Remove it when the panel closes. |
| Global `NSEvent` monitor | Accessibility trust for key events | Do not use as a fallback; it conflates the text-inspection permission with keyboard monitoring. |
| Narrow active `CGEventTap` | Input Monitoring for keyboard monitoring; Accessibility is separately required for AX caret/text access; validate actual active-filter TCC behavior on-device | Normally pass-through; during activation handoff consume only Arrow, Command-C, and Escape as bounded semantic commands. Never retain raw events or characters. Capture source/caret before making the overlay key; handle all later commands locally. |

## Shared keyboard and mouse boundary behavior

The overlay stores an immutable anchor boundary and movable focus boundary. A
keyboard arrow moves one grid boundary or visual row. Mouse points snap to the
same boundaries, so dragging exactly one character width selects one column.
Normalization when focus crosses anchor is identical for both paths.

```swift
struct SelectionRect {
    var screenID: CGDirectDisplayID
    /// AppKit screen coordinates: global space, bottom-left origin, in points,
    /// as produced by `window.convertToScreen(_:)`. Consumers that intersect
    /// this rect with AX/CG geometry (top-left origin) must apply the y-flip
    /// defined by the issue #9 coordinate contract.
    var rectInScreenPoints: CGRect
}

final class SelectionOverlayView: NSView {
    private var anchor: CGPoint?
    private var current: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    // Without this, the first click on a not-yet-key panel can be consumed by
    // window activation instead of starting the drag ("swallowed first click").
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        current = anchor
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        freezeSelection()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: cancelSelection()  // Escape
        case 8 where event.modifierFlags.contains(.command): // Command-C
            guard state == .selected, selection.columnCount > 0 else {
                showActionableEmptySelectionStatus()
                return
            }
            freezeCurrentGeneration()
            copySelection()
        default: super.keyDown(with: event)
        }
    }
}
```

Drawing should use vector paths in AppKit points. A simple fill plus stroke is
enough for the spike:

| Element | Suggested treatment |
|---|---|
| Outside region | Optional translucent dim, low opacity. |
| Selection fill | Clear or very light tint so the underlying text remains readable. |
| Selection border | 1-2 point high-contrast stroke. |
| Handles | Out of MVP unless post-drag adjustment is included. |

## Freeze, copy, and cancel

MVP behavior:

| Command | Trigger | Result |
|---|---|---|
| Cancel | Escape, secondary click, or explicit cancel button if later added | Consume the event, close every panel through the idempotent cleanup path, clear the current generation, and return `nil`. Secondary click never reaches the source app while the overlay owns input. |
| Freeze | Shift release after keyboard adjustment, or mouse up after a drag | Keep the zero- or nonzero-width selection visible; do not mutate the clipboard. |
| Copy | Command-C while a nonzero-width selection is frozen | Return `SelectionRect` to extraction/copy and close after success or terminal failure. |
| Empty width | Command-C while the frozen column range is empty | Consume the command, retain the caret/multi-cursor overlay, leave the clipboard unchanged, and show actionable status. |

Do not use a point-size threshold for production semantics. Snap to measured grid
boundaries: one character width is exactly one selected column, and endpoint rows
are inclusive. The historical prototype's 4-point threshold remains prototype-
only evidence.

## Coordinate spaces

Store selection geometry in screen-space points, not pixels.

Recommended conversion flow:

1. Receive `event.locationInWindow`.
2. Convert to overlay view coordinates with `view.convert(_:from: nil)`.
3. Normalize the rectangle in overlay view coordinates.
4. Convert the normalized view rectangle to window coordinates with
   `view.convert(_:to: nil)`.
5. Convert the window rectangle to screen coordinates with
   `window.convertToScreen(_:)`.
6. Attach the source `NSScreen` / `CGDirectDisplayID`.
7. Only when a later screenshot/OCR pipeline needs pixels, convert with the
   corresponding `NSWindow`, `NSView`, or `NSScreen` backing conversion API.

Output contract: `SelectionRect.rectInScreenPoints` is AppKit screen space —
global coordinates, **bottom-left origin**, in points. The Accessibility
extraction path (issue #6 spike) intersects this rectangle with AX range bounds,
which use a **top-left origin**. That y-flip (and any point/pixel normalization)
must be performed exactly once, at the boundary defined by the coordinate
contract in issue #9 — not ad hoc inside individual components.

Important coordinate notes:

| Topic | Guidance |
|---|---|
| AppKit points | Use points for overlay layout and drawing. |
| Flipped views | If `SelectionOverlayView.isFlipped == true`, centralize conversion so y-axis assumptions do not leak. |
| Screen coordinates | Use `NSScreen.frame` for full-screen overlays; `visibleFrame` excludes menu bar/dock areas and is not suitable for selecting text under those regions. |
| Y-axis flip vs AX/CG | AppKit screen coordinates use a bottom-left origin; Accessibility (`kAXBoundsForRangeParameterizedAttribute`) and Core Graphics (`CGDisplayBounds`, `CGEvent`) use a top-left origin. Keep `SelectionRect` AppKit-native and apply the flip once at the issue #9 contract boundary. |
| Core Graphics display bounds | If later bridging to `CGDisplayBounds`, be explicit about coordinate origins and transforms. |
| Pixel alignment | Use `convertRectToBacking` / `backingAlignedRect` for pixel-sensitive work; do not multiply by `backingScaleFactor` throughout the app. |

## Multi-display behavior

Use one overlay panel per `NSScreen.screens` entry.

Recommended MVP:

| Case | Behavior |
|---|---|
| Drag starts on one display | Only that display owns the active rectangle. Other overlay panels remain transparent and idle. |
| Keyboard anchor is on one display | The caret's display owns the rectangle and is the only panel made key. |
| Mouse down occurs on another display while armed | Transfer session/display ownership to the clicked panel before dragging; only that panel becomes key. |
| Drag crosses display boundary | Clamp to the starting display for MVP. Cross-display selection can be a later feature. |
| Multiple Retina scales | Keep rects in points and attach the owning screen. Convert to backing only in a later capture pipeline. |
| Display added/removed during selection | Cancel the selection and close every panel. A retry always starts a new session with fresh display geometry. |
| Full-screen app on another display | `canJoinAllSpaces` plus `fullScreenAuxiliary` should be tested. If `.statusBar` does not appear, test `.screenSaver` as a temporary fallback. |
| Separate Spaces enabled | Check `NSScreen.screensHaveSeparateSpaces` during diagnostics; behavior can differ when displays have independent Spaces. |

The MVP should not allow a single selection rectangle to span displays. Splitting
or stitching geometry across displays belongs to the later capture/OCR layer.

## Retina scaling

The overlay should draw in AppKit points and let AppKit handle display backing
changes. Apple's high-resolution guidance recommends conversion APIs when
backing coordinates are needed and notes that scale factors are object-specific.

Rules for the MVP:

| Rule | Why |
|---|---|
| Do not store pixels in overlay state. | Selection UX is independent of screenshot/OCR implementation. |
| Do not cache `backingScaleFactor` as a global setting. | Different screens/windows can have different backing characteristics. |
| Redraw vector paths when the panel moves or display configuration changes. | Vector drawing remains sharp across scale changes. |
| Convert with the object that owns the coordinate space. | Round-tripping through the same `NSView`, `NSWindow`, or `NSScreen` avoids subtle errors. |

## Focus behavior

Desired behavior: selection mode is visually modal but not app-activating.

Practical approach:

1. Retain the captured source identity only in session memory; do not log process,
   bundle, window, caret, rectangle, or text data and do not manipulate other apps.
2. Show non-activating panels with `orderFrontRegardless()`.
3. Use the event-tap transition guard to protect immediate Grid commands after
   double-Shift. Capture an immutable
   source process/window/element context and caret before making exactly one
   owning-display overlay panel key and first responder.
4. Keep a frozen selection visible until Escape, successful Command-C copy, or a
   terminal failure closes the panels.
5. Do not call `NSApp.activate(ignoringOtherApps:)` in the default MVP path.

Known tradeoff: a non-activating overlay that receives mouse events intercepts
clicks while selection mode is active. The frozen overlay remains input-owning
and must not become click-through. If its panel is no longer key or the intended
view is no longer first responder, cancel immediately so Command-C cannot leak to
the source app. Matched Grid commands are consumed through AppKit routing
(`performKeyEquivalent` where appropriate); a global monitor is not a fallback.

## Permissions

Overlay drawing alone should not require Screen Recording, Accessibility, or
Input Monitoring permissions. The panel draws GridSelect-owned UI; it does not
read pixels or inspect another app.

Permission boundaries:

| Capability | Permission implication | MVP status |
|---|---|---|
| Transparent overlay window | No special TCC permission expected | In scope |
| Local mouse drag inside overlay | No special TCC permission expected | In scope |
| Local Shift+Arrow, Command-C, and Escape while overlay is key | No extra TCC permission beyond the activation/text capabilities | In scope |
| Double-Shift monitoring plus bounded activation guard while another app remains focused | Active `CGEventTap`; Input Monitoring is the documented monitoring gate, Accessibility is separately needed for AX, and active-filter TCC behavior must be verified; only Arrow, Command-C, and Escape may be consumed during handoff | In scope |
| Reading screen pixels with ScreenCaptureKit | Screen Recording permission | Out of MVP |
| Inspecting another app's caret/text geometry via AX APIs | Accessibility trust | In scope through #14 |

If a later version needs screenshot/OCR, handle Screen Recording permission in a
separate capture spike so the overlay UX does not inherit unnecessary privacy
friction.

## Historical prototype checklist

This PR includes a minimal prototype at
`spikes/macos-overlay/overlay-rectangle-prototype.swift`. It is intentionally a
single-file AppKit prototype, not production scaffolding.

Run syntax/type validation:

```sh
swiftc -typecheck spikes/macos-overlay/overlay-rectangle-prototype.swift
```

Run the interactive prototype from a GUI session:

```sh
swift spikes/macos-overlay/overlay-rectangle-prototype.swift
```

Useful validation variants:

```sh
swift spikes/macos-overlay/overlay-rectangle-prototype.swift --help
swift spikes/macos-overlay/overlay-rectangle-prototype.swift --diagnostics
swift spikes/macos-overlay/overlay-rectangle-prototype.swift --level=floating --diagnostics
swift spikes/macos-overlay/overlay-rectangle-prototype.swift --auto-cancel-after=1
```

Prototype options:

| Option | Purpose |
|---|---|
| `--level=floating\|statusBar\|screenSaver` | Tests the overlay at a specific AppKit window level. Default is `statusBar`. |
| `--min-size=<points>` | Changes the historical prototype's minimum width and height before mouse-up returns a rectangle. Production freezes instead of copying. |
| `--diagnostics` | Prints display IDs, screen frames, visible frames, backing scale factors, and `screensHaveSeparateSpaces`, then exits without showing overlays. |
| `--auto-cancel-after=<seconds>` | Shows the overlay session and cancels automatically after the given delay. This is useful for a non-interactive smoke test that proves the AppKit session can start and close. |

The prototype keeps anchor/current points in overlay view coordinates, converts
the normalized rectangle through view -> window -> screen, makes the panel key
for `keyDown`, and installs a local key monitor fallback for Escape. It clamps
drag points to the starting screen's overlay view bounds so the MVP behavior
stays single-display even if the pointer crosses a display boundary.

Historical prototype manual validation covers only implemented behavior:

| Scenario | Expected result |
|---|---|
| Terminal/editor/browser normal window | Overlay appears above the target and drag updates the rectangle smoothly. |
| First click immediately after the overlay appears | The very first mouse down starts the drag; it is not consumed by window/key activation. |
| Escape during drag | Overlay closes with no selection. |
| Mouse-up confirm | The prototype closes and prints the non-empty rectangle. This is not production freeze/copy evidence. |
| External display | Overlay appears on every display; selection is associated with the display where the drag began. |
| Retina display | Rect size and drawn border remain stable in points; no manual pixel scaling is needed. |
| Full-screen app | `.statusBar` plus collection behavior is tested; fallback level is documented if needed. |
| App focus | Underlying app should remain the user's apparent context; GridSelect should not become visibly activated. |

### Production implementation validation checklist

Run this checklist only against the production implementation, not the historical
prototype:

| Scenario | Expected result |
|---|---|
| Double-Shift handoff | The approved activation-to-ready contract is visible and immediate Grid input follows that contract without reaching the source app. |
| Keyboard zero-width start | Caret/multi-cursor affordance begins at zero width; Shift release freezes it. |
| Keyboard boundary movement | Right once selects one column; Up/Down spans adjacent rows while preserving width; anchor crossing and repeat match fixtures. |
| Mouse boundary movement | One character-width drag selects one column; row and midpoint snapping match pure fixtures. |
| Frozen ownership | Overlay remains key/first responder and not click-through; zero-width first mouse down can re-anchor. |
| Command-C | Zero width leaves clipboard unchanged; nonzero width starts one copy and consumes repeats without source-app copy. |
| Terminal cleanup | Escape, result, permission loss, listener disablement, source/responder mismatch, and display invalidation close all session resources once. |

## Prototype validation status

Validation date: 2026-07-09 JST

Automated and non-interactive checks completed in a normal macOS GUI session:

| Check | Result | Evidence |
|---|---|---|
| Typecheck | Passed | `swiftc -typecheck spikes/macos-overlay/overlay-rectangle-prototype.swift` |
| Help path | Passed | `swift spikes/macos-overlay/overlay-rectangle-prototype.swift --help` printed usage and exited. |
| Diagnostics path | Passed | `swift spikes/macos-overlay/overlay-rectangle-prototype.swift --diagnostics --level=statusBar` printed two screens and exited. |
| Overlay session smoke | Passed | `swift spikes/macos-overlay/overlay-rectangle-prototype.swift --auto-cancel-after=1` started the AppKit overlay session, printed screen diagnostics, then cancelled and exited. |

Observed diagnostic environment:

| Screen | Display ID | Frame | Visible frame | Backing scale |
|---|---:|---|---|---:|
| 0 | 1 | `(0.0, 0.0, 2560.0, 1080.0)` | `(0.0, 0.0, 2560.0, 1050.0)` | 2.0 |
| 1 | 3 | `(2560.0, 78.0, 1920.0, 1080.0)` | `(2560.0, 78.0, 1920.0, 1050.0)` | 1.0 |

`NSScreen.screensHaveSeparateSpaces` reported `true` after initializing
`NSApplication.shared`. The prototype now initializes AppKit before diagnostics
so diagnostics and an actual overlay run observe the same screen environment.

Manual interaction results:

| Scenario | Status | Notes |
|---|---|---|
| Visual confirmation that overlays appear over Terminal/editor/browser | Blocked for this agent run | The background Codex thread can start and auto-cancel the AppKit session, but it cannot honestly verify screen pixels or human-visible stacking. |
| Drag update | Blocked for this agent run | Requires human mouse interaction over the overlay. |
| Escape cancel | Blocked for this agent run | The code path is present through `keyDown` and a local key monitor, but it needs interactive validation. |
| Mouse-up confirm and printed rectangle | Blocked for this agent run | Requires human drag interaction; expected output is `selection screenID=... x=... y=... w=... h=...`. |
| Full-screen Space behavior | Blocked for this agent run | Requires a human to place a target app in full-screen mode and test `.statusBar`, then `.screenSaver` only if needed. |

The automated smoke test proves the prototype can create overlay panels and
cleanly close the session in this environment. It does not replace manual
validation of rectangle drawing, pointer interaction, or window stacking.

## Acceptance criteria mapping

| Issue #7 criterion | Current evidence | Remaining work |
|---|---|---|
| A prototype can display and update a rectangle over another app. | The AppKit prototype typechecks and the auto-cancel smoke run starts/closes an overlay session. Drawing and drag-update code paths exist. | Human manual validation must confirm visible stacking and drag updates over Terminal/editor/browser. |
| The report documents window level, input handling, and focus behavior. | The report covers `.floating`, `.statusBar`, `.screenSaver`, non-activating panels, local mouse/key handling, and focus tradeoffs. | Record exact manual results for the chosen macOS version after interaction testing. |
| Basic multi-display and Retina coordinate considerations are documented. | The report documents point-based storage, one panel per screen, single-display clamping, and diagnostics from one Retina and one non-Retina display. | Human validation should confirm drag behavior on each physical display and across the boundary. |
| Known permission requirements and limitations are listed. | The report states overlay-only behavior should not require Screen Recording, Accessibility, or Input Monitoring, and lists when those permissions would apply later. | Reconfirm during manual validation that no unexpected TCC prompt appears. |

## Risks and follow-ups

| Risk | Mitigation |
|---|---|
| `.statusBar` may not appear over every full-screen Space. | Test `.screenSaver` as a session-only fallback and document exact OS behavior. |
| The first click on a non-activating panel can be consumed by activation instead of starting the drag. | Override `acceptsFirstMouse(for:)` in the overlay view and verify the first-drag scenario in the prototype checklist. |
| Modifier event ordering and key repeat can vary. | Keep double-Shift recognition and local keyboard adjustment as pure state machines with timing/repeat tests. |
| Stage Manager/Spaces behavior varies by system settings. | Include `screensHaveSeparateSpaces`, full-screen, and Stage Manager states in manual test notes. |
| Future screenshot/OCR needs pixel-perfect conversion. | Keep this spike point-based and defer backing conversion to capture implementation. |
| Very high overlay levels can obscure system UI. | Use the least powerful level that passes tests and close panels at cancel or the copy terminal result. |

## Final MVP approach

Implement a short-lived `SelectionOverlaySession` that:

1. Builds one transparent non-activating `NSPanel` per `NSScreen`.
2. Uses `.statusBar` level by default with `.canJoinAllSpaces` and
   `.fullScreenAuxiliary`.
3. Captures drag events locally in the overlay view.
4. Accepts a keyboard caret anchor plus Shift+Arrow adjustments or a first-click
   mouse anchor plus drag adjustments.
5. Freezes on Shift/mouse release and remains visible without copying.
6. Returns the frozen rectangle only on Command-C; cancels on Escape or invalid
   display changes.
7. Returns a `SelectionRect` in AppKit screen-space points (bottom-left origin)
   plus the owning display ID, per the coordinate contract to be fixed in #9.
8. Verifies key window/first responder, source identity, permission state, and
   session generation before accepting input or publishing a copy result.
9. Closes every panel, event/local monitor, run-loop source, and session buffer
   through one idempotent cleanup path after cancel, terminal result, permission
   loss, listener disablement, display invalidation, or responder loss.

This keeps the issue #7 spike focused on macOS overlay behavior and leaves OCR,
screenshot capture, and app-specific optimizations for later work.
