# macOS overlay window behavior spike

Issue: https://github.com/Saber5656/GridSelect/issues/7

## Scope

This spike documents an MVP approach for drawing and adjusting a rectangular
selection region above other macOS apps. It intentionally excludes OCR,
screenshot saving, image parsing, and app-specific overlay optimization. It also
does not scaffold an app.

The goal is to identify the window, input, focus, coordinate, multi-display,
Retina, and permission decisions that should shape the first prototype.

## Recommendation

Use one borderless, transparent `NSPanel` per `NSScreen` while the selection
session is active. Configure it as a non-activating panel, keep it above normal
app windows, draw only the selection affordance, and close it immediately on
cancel or confirm.

Recommended MVP defaults:

| Concern | MVP choice | Reason |
|---|---|---|
| Window class | `NSPanel` subclass | Panels are intended for auxiliary UI, and `.nonactivatingPanel` is panel-oriented. |
| Style mask | `[.borderless, .nonactivatingPanel]` | No title bar or normal window chrome, and showing the panel should not activate GridSelect. |
| Transparency | `isOpaque = false`, `backgroundColor = .clear`, custom `NSView` drawing | The overlay can show the underlying app while still receiving mouse events. |
| Window level | Start with `.statusBar`; test `.floating` and `.screenSaver` as fallbacks | `.floating` may be enough for normal windows. `.statusBar` is a stronger MVP default. `.screenSaver` is very high and should be used only during active selection if required. |
| Spaces/full screen | `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` | Selection should appear in the active Space and above full-screen apps during the session. |
| Mouse handling | Overlay captures mouse events; do not set `ignoresMouseEvents` while selecting | Dragging the rectangle requires the overlay to receive mouse down/drag/up. |
| Keyboard handling | Prefer panel/view `keyDown` plus a local event monitor for Escape/Return | Avoid global key monitoring permissions in the MVP. |
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
| Accessibility trust | [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) | Accessibility trust is relevant only if the app later uses Accessibility APIs or permissioned global input strategies. |

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
    panel.contentView = SelectionOverlayView(
        frame: NSRect(origin: .zero, size: screen.frame.size)
    )
    panel.orderFrontRegardless()
    return panel
}
```

Notes:

| Setting | Why it matters |
|---|---|
| `canBecomeKey` | Borderless panels often need an explicit key-window strategy for Escape/Return handling. |
| `canBecomeMain = false` | The overlay is a transient tool, not the document/main surface. |
| `orderFrontRegardless()` | Shows the overlay without activating GridSelect or changing main/key windows by itself. |
| `ignoresMouseEvents = false` | Required for drag capture. For passive display after selection, it can be set to `true` or the panel can be closed. |

## Input handling

The MVP should keep input local to the overlay while it is visible.

State machine:

| State | Event | Action |
|---|---|---|
| `idle` | Mouse down inside overlay | Record anchor in window coordinates and transition to `dragging`. |
| `dragging` | Mouse dragged | Normalize anchor/current point into a rectangle and redraw. |
| `dragging` | Mouse up | Either confirm immediately or transition to `adjusting`, depending on UX choice. |
| `dragging` or `adjusting` | Escape | Cancel, close panels, return no selection. |
| `adjusting` | Return | Confirm current selection. |
| Any active state | Display configuration change | Cancel or rebuild panels and keep the previous rect only if it still belongs to a live screen. |

For the first usable path, use drag-to-confirm on mouse up and Escape to cancel.
Return-to-confirm becomes useful only if the MVP adds handles or post-drag
adjustment.

Avoid global mouse monitors for rectangle dragging. If the panel covers each
screen and accepts mouse events, mouse down/drag/up are local overlay events.
Global monitors add complexity, cannot prevent normal event delivery, and move
the design toward accessibility/input-monitoring permission questions.

Keyboard handling options:

| Option | Permission profile | Tradeoff |
|---|---|---|
| `keyDown` on the overlay view/panel | No extra permission | Works if the panel is key during selection. |
| Local `NSEvent` monitor | No extra permission | Useful for Escape/Return while the app is dispatching overlay events. Remove it when the panel closes. |
| Global `NSEvent` monitor | Accessibility trust for key events | Avoid in MVP; use only if non-activating keyboard handling proves unreliable. |
| `CGEventTap` | Likely Input Monitoring for keyboard use | Out of scope for this overlay spike. |

## Drag rectangle behavior

The overlay view should store the anchor and current point in its local
coordinate space and normalize on every update.

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
        confirmSelection()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: cancelSelection()  // Escape
        case 36: confirmSelection() // Return
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

## Cancel and confirm

MVP behavior:

| Command | Trigger | Result |
|---|---|---|
| Cancel | Escape, secondary click, or explicit cancel button if later added | Close all overlay panels and return `nil`. |
| Confirm | Mouse up after a non-empty drag | Close all overlay panels and return `SelectionRect`. |
| Empty drag | Mouse up with width/height below threshold | Treat as cancel or keep waiting; document the chosen threshold. |

Recommended threshold: at least 4 x 4 points before confirming. This prevents
accidental clicks from becoming selections.

## Coordinate spaces

Store selection geometry in screen-space points, not pixels.

Recommended conversion flow:

1. Receive `event.locationInWindow`.
2. Convert to overlay view coordinates with `view.convert(_:from: nil)`.
3. Normalize the rectangle in view/window coordinates.
4. Convert the rectangle to screen coordinates with `window.convertToScreen(_:)`.
5. Attach the source `NSScreen` / `CGDirectDisplayID`.
6. Only when a later screenshot/OCR pipeline needs pixels, convert with the
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
| Drag crosses display boundary | Clamp to the starting display for MVP. Cross-display selection can be a later feature. |
| Multiple Retina scales | Keep rects in points and attach the owning screen. Convert to backing only in a later capture pipeline. |
| Display added/removed during selection | Cancel the selection and close panels, or rebuild and ask the user to retry. |
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

1. Record the previously active app/window only if needed for diagnostics; do
   not attempt to manipulate other apps.
2. Show non-activating panels with `orderFrontRegardless()`.
3. Make the overlay panel key only if required for Escape/Return.
4. Close panels immediately on cancel/confirm.
5. Do not call `NSApp.activate(ignoringOtherApps:)` in the default MVP path.

Known tradeoff: a non-activating overlay that receives mouse events will still
intercept clicks while the selection session is active. That is acceptable for a
drag-selection mode. After confirmation, close the panel rather than leaving a
click-through overlay alive.

## Permissions

Overlay drawing alone should not require Screen Recording, Accessibility, or
Input Monitoring permissions. The panel draws GridSelect-owned UI; it does not
read pixels or inspect another app.

Permission boundaries:

| Capability | Permission implication | MVP status |
|---|---|---|
| Transparent overlay window | No special TCC permission expected | In scope |
| Local mouse drag inside overlay | No special TCC permission expected | In scope |
| Local Escape/Return while overlay is key | No special TCC permission expected | In scope |
| Global keyboard monitoring while another app remains focused | Accessibility trust for `NSEvent` key monitoring; Input Monitoring may apply to lower-level event taps | Out of MVP |
| Reading screen pixels with ScreenCaptureKit | Screen Recording permission | Out of MVP |
| Inspecting another app's UI via AX APIs | Accessibility trust | Out of MVP |

If a later version needs screenshot/OCR, handle Screen Recording permission in a
separate capture spike so the overlay UX does not inherit unnecessary privacy
friction.

## MVP prototype checklist

Manual validation should cover:

| Scenario | Expected result |
|---|---|
| Terminal/editor/browser normal window | Overlay appears above the target and drag updates the rectangle smoothly. |
| First click immediately after the overlay appears | The very first mouse down starts the drag; it is not consumed by window/key activation. |
| Escape during drag | Overlay closes with no selection. |
| Mouse-up confirm | Overlay closes and returns a non-empty rect in screen points. |
| External display | Overlay appears on every display; selection is associated with the display where the drag began. |
| Retina display | Rect size and drawn border remain stable in points; no manual pixel scaling is needed. |
| Full-screen app | `.statusBar` plus collection behavior is tested; fallback level is documented if needed. |
| App focus | Underlying app should remain the user's apparent context; GridSelect should not become visibly activated. |

## Risks and follow-ups

| Risk | Mitigation |
|---|---|
| `.statusBar` may not appear over every full-screen Space. | Test `.screenSaver` as a session-only fallback and document exact OS behavior. |
| The first click on a non-activating panel can be consumed by activation instead of starting the drag. | Override `acceptsFirstMouse(for:)` in the overlay view and verify the first-drag scenario in the prototype checklist. |
| Non-activating keyboard handling can be inconsistent. | Use mouse-up confirm for MVP; add local monitor; consider explicit UI affordance before global monitoring. |
| Stage Manager/Spaces behavior varies by system settings. | Include `screensHaveSeparateSpaces`, full-screen, and Stage Manager states in manual test notes. |
| Future screenshot/OCR needs pixel-perfect conversion. | Keep this spike point-based and defer backing conversion to capture implementation. |
| Very high overlay levels can obscure system UI. | Use the least powerful level that passes tests and close panels immediately after selection. |

## Final MVP approach

Implement a short-lived `SelectionOverlaySession` that:

1. Builds one transparent non-activating `NSPanel` per `NSScreen`.
2. Uses `.statusBar` level by default with `.canJoinAllSpaces` and
   `.fullScreenAuxiliary`.
3. Captures drag events locally in the overlay view.
4. Confirms on mouse up when the normalized rectangle exceeds a small threshold.
5. Cancels on Escape or invalid display changes.
6. Returns a `SelectionRect` in AppKit screen-space points (bottom-left origin)
   plus the owning display ID, per the coordinate contract to be fixed in #9.
7. Closes all overlay panels before any future capture/OCR step begins.

This keeps the issue #7 spike focused on macOS overlay behavior and leaves OCR,
screenshot capture, and app-specific optimizations for later work.
