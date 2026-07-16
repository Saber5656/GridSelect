# macOS Global Shortcut and Permission Flow Spike

Date: 2026-07-05

Issue: [#8 Spike global shortcut and permission flow on macOS](https://github.com/Saber5656/GridSelect/issues/8)

## Summary

Decision update, 2026-07-15: use a narrowly active `CGEventTap` with
**Input Monitoring** for the approved production interaction. The user enters
Grid mode by double-tapping Shift, keeps the second Shift press held while Arrow
keys adjust a caret-anchored rectangle, releases Shift to freeze it, and presses
Command-C to copy. Escape cancels. This modifier-only gesture and held-key state
cannot be expressed with Carbon hot-key registration.

The event tap must:

- Listen for `.flagsChanged` plus `.keyDown`, and for `.keyUp` only while a
  bounded matching-release tail may exist. Outside the recognized handoff,
  key-down is only a content-blind signal that invalidates a pending double-Shift
  candidate; do not inspect its key code or characters there. During the bounded
  handoff only, transiently inspect the virtual key code and Command modifier to
  classify Arrow, Command-C, Escape, or `other`; never decode characters or
  retain/log the inspected values.
- Return every event unchanged outside the recognized activation handoff. During
  that bounded handoff, consume only Arrow, Command-C, and Escape into semantic
  commands; always pass Shift release and ordinary input through. A consumed
  guarded key-down retains only its semantic key class for at most 500 ms so the
  matching key-up is also consumed after handoff; unrelated and expired key-ups
  pass through, and disablement clears the tail.
- Retain no typed-key history and never log raw key values.
- Be enabled only after an explicit user action grants Input Monitoring, and be
  torn down or disabled when permission is absent or revoked.

**Accessibility** remains a separate gate for resolving the frontmost text
element, insertion-caret geometry, and text bounds. After caret capture, the
overlay becomes the local key responder for Shift+Arrow, Command-C, and Escape;
these commands are not monitored globally or delivered to the source app. The
historical Carbon
`Command-Shift-G` prototype remains useful evidence about the rejected low-
permission alternative, but it is not the MVP activation path or user-facing
shortcut.

For the pre-alpha, prefer Developer ID distribution outside the Mac App Store while the Accessibility text-extraction and overlay spikes are still being validated.

## Scope

In scope:

- macOS-only global shortcut options for a Swift + SwiftUI/AppKit native app.
- Event taps, hotkeys, Accessibility, and Input Monitoring permission behavior.
- Sandbox, Mac App Store, and non-App Store pre-alpha implications.
- Missing-permission behavior and minimal user-facing setup copy.
- Recommended MVP permission flow.

Out of scope:

- Windows/Linux shortcuts.
- Full settings UI.
- Shortcut sync.
- App scaffolding.

## Option Matrix

| Option | Permission surface | App Sandbox / App Store fit | Pros | Risks | Recommendation |
|---|---|---|---|---|---|
| `RegisterEventHotKey` (Carbon HIToolbox), directly or via KeyboardShortcuts / HotKey wrappers | **None known** — no Input Monitoring and no Accessibility | Works in sandboxed and Mac App Store apps | Purpose-built hot-key registration; receives only one registered combo | Cannot express double-Shift or held Shift+Arrow state; `Command-Shift-G` conflicts with Finder; legacy Carbon lineage | **Rejected for production interaction**; retain the prototype as historical evidence |
| `CGEvent.tapCreate` / `CGEventTapCreate` active event tap | Input Monitoring is the documented keyboard-monitoring gate. GridSelect separately requires Accessibility for AX text/caret access. Exact active-filter TCC behavior remains an on-device evidence gate. | Works outside the active app; actual sandbox/App Store viability remains an evidence gate | Can observe modifier-only gestures and prevent immediate Grid commands from mutating the source before overlay readiness | Event suppression broadens responsibility; callback, timeout, queue bounds, TCC behavior, and permission revocation must fail closed | **Use for activation and the bounded transition guard only** |
| `NSEvent.addGlobalMonitorForEvents` | Accessibility for key-related events | Poorer fit; Apple DTS recommends `CGEventTap` instead for sandboxed keyboard monitoring | Simple AppKit API; good for quick local experiments | Can only observe, key events need Accessibility — the wrong permission for this job | Avoid for MVP shortcut |
| Local app shortcuts / SwiftUI commands | No global permission | App-only | Best UX when GridSelect is frontmost | Does not work globally | Use only for in-app commands |

## Historical Prototype: Hot-Key Registration

This section records the original least-permission recommendation and prototype.
The 2026-07-15 interaction decision supersedes it for production because Carbon
cannot represent double-Shift or Grid-mode held-key state.

Implementation sketch (illustrative, not production code):

```swift
import Carbon.HIToolbox

var hotKeyRef: EventHotKeyRef?
let hotKeyID = EventHotKeyID(signature: OSType(0x4753_4C54), id: 1) // 'GSLT'

// The default shortcut must include ⌘ or ⌃ — see the Sequoia note below.
let status = RegisterEventHotKey(
    UInt32(kVK_ANSI_G),
    UInt32(cmdKey | shiftKey),
    hotKeyID,
    GetEventDispatcherTarget(),
    0,
    &hotKeyRef
)

var hotKeyEvent = EventTypeSpec(
    eventClass: OSType(kEventClassKeyboard),
    eventKind: UInt32(kEventHotKeyPressed)
)
InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
    // Read the EventHotKeyID via GetEventParameter(kEventParamDirectObject,
    // typeEventHotKeyID, ...) and enter selection mode when it matches.
    return noErr
}, 1, &hotKeyEvent, nil, nil)
```

In practice the MVP should use a wrapper rather than raw Carbon wiring: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) adds a user-facing shortcut recorder (useful for #16) and is actively maintained; [HotKey](https://github.com/soffes/HotKey) is a minimal alternative.

Behavior and constraints:

| Concern | Detail | MVP handling |
|---|---|---|
| TCC | No permission prompt is expected for registration or delivery | Verify on-device as part of the prototype (see validation plan) |
| macOS Sequoia modifier restriction | 15.0 intentionally rejects Carbon hot keys whose only modifiers are Shift and/or Option with `eventInternalErr` (-9868) | Historical reason Carbon cannot supply this gesture; production uses the permissioned event tap |
| Registration failure / conflicts | `RegisterEventHotKey` returns a non-zero `OSStatus` when registration fails | Show a "shortcut inactive" state and let the user pick another combo (#16) |
| Expressiveness | Cannot express modifier-only activation or held-key state | Disqualifies Carbon for the approved Grid mode interaction |
| DTS positioning | Apple DTS describes the API as legacy and recommends `CGEventTap` for keyboard *monitoring* | The approved flow requires a narrow monitored state machine, so use the Core Graphics path |

## Production Path: Narrow Active CGEventTap

The approved modifier-only gesture satisfies the former fallback trigger. The
production listener is normally pass-through and becomes an active guard only
for the activation handoff:

- Use `.cgSessionEventTap`, `.headInsertEventTap`, and `.defaultTap`.
- Listen for `.flagsChanged` and `.keyDown`; outside the handoff, a key-down event
  only clears a pending double-Shift candidate without reading key code or
  characters.
- Match double-Shift and return original events unchanged outside the handoff.
- Do not log modifier or key events. A coarse `gridModeEntered` diagnostic is enough.
- Use `CGPreflightListenEventAccess()` as the Input Monitoring permission gate.
  If permission is available but `CGEvent.tapCreate` returns `nil`, treat it as an
  input-listener setup failure, move the UI into “Input listener failed,” and
  provide Recheck guidance. This remains distinct from the installed callback
  intentionally returning `nil` for a consumed guard event.

Double-Shift recognition uses the macOS system double-click interval rather than
a hard-coded timing constant. It requires Shift down/up followed by a second
Shift down with no intervening non-modifier key. Releasing the second Shift before
a valid keyboard rectangle exists keeps Grid mode armed for mouse selection.
Before making the overlay key, capture the frontmost application and insertion-
caret geometry. The overlay then handles Shift+Arrow, Command-C, and Escape as
local events, preventing normal source-app selection or copy side effects.

The event-tap callback performs only timing/state updates and, during the bounded
handoff, transient virtual-key/modifier classification. It dispatches a
generation-tagged activation or semantic signal before immediately returning the
original event or `nil` according to the guard rule. Permission checks,
Accessibility calls, and AppKit work run on the main actor after confirming that
the signal still belongs to the current generation.
`tapDisabledByTimeout` and `tapDisabledByUserInput` make the listener inactive,
cancel any active session through the shared idempotent cleanup path, and require
an explicit Recheck instead of automatic re-enablement.

On the recognized second Shift down, the callback enters a generation-tagged
transition guard before dispatching AX/AppKit work. Until the owning overlay is
key and its expected first responder is verified:

- Arrow key-down becomes a direction/repeat semantic and returns `nil`.
- Command-C becomes `copyRequested` and returns `nil`.
- Escape becomes `cancelRequested` and returns `nil`.
- Second-Shift release returns the original event but appends an ordered `freeze`
  state marker. Other Shift modifier changes pass through without an entry.
- Any other key-down cancels the pending Grid session and returns the event.
- The queue capacity is exactly 32 entries. Every Arrow/Command-C/Escape repeat
  semantic and `freeze` marker consumes one entry. An attempted 33rd entry,
  setup failure, or a 500 ms deadline cancels before append and discards the
  generation without clipboard mutation.

After readiness, MainActor drains current-generation semantics in order. Arrow
semantics before `freeze` adjust the boundary, `freeze` freezes the selection,
and Arrow semantics after `freeze` remain consumed but are not applied. Command-C
is actionable only after a nonzero selection is frozen; an earlier request is
consumed without pasteboard mutation. Overlay-local routing then owns subsequent
Grid commands. No raw event, character, or typed-key history crosses the callback
boundary.

The event tap docs say `CGEvent.tapCreate` creates an event tap and returns `nil` if the tap cannot be created. Requested event types can be removed from the mask when monitoring is not permitted, and an empty mask causes creation to fail. See [CGEvent.tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/1454426-tapcreate).

Apple DTS recommends `CGEventTap` over `NSEvent` global monitors for sandboxed keyboard monitoring because the former uses Input Monitoring rather than Accessibility, with `CGPreflightListenEventAccess` and `CGRequestListenEventAccess` as the matching check/request APIs. See [Apple Developer Forums thread 707680](https://developer.apple.com/forums/thread/707680?answerId=716892022#716892022).

Input Monitoring specifics:

| Need | API |
|---|---|
| Check whether the app can listen for input events | `CGPreflightListenEventAccess()` or `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` |
| Request the system prompt | `CGRequestListenEventAccess()` or `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` |
| User-facing settings location | `System Settings > Privacy & Security > Input Monitoring` |

Apple Support describes Input Monitoring as the permission that allows apps to monitor keyboard, mouse, or trackpad input while the user is using other apps. See [Control access to input monitoring on Mac](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac).

Implementation notes:

- Request only after an explicit user action, such as "Enable Shortcut".
- Recheck on app activation and before starting the event tap.
- Recheck both permissions immediately before entering Grid mode and immediately
  before extraction/copy. Treat an Accessibility permission error as a terminal
  session failure.
- If the request returns `false` or the event tap still fails, show manual setup instructions and a "Recheck" action.
- Assume the system prompt is one-shot per app identity; keep the bundle identifier and signing identity stable during pre-alpha to reduce TCC reset churn.

## Accessibility

Do not use Accessibility as a substitute for Input Monitoring. Use it when
GridSelect needs to inspect another app, including resolving the insertion caret
that anchors keyboard selection and extracting text geometry.

| Need | API / behavior |
|---|---|
| Check whether the process is trusted for Accessibility | `AXIsProcessTrusted()` |
| Request an Accessibility prompt | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)` |
| User-facing settings location | `System Settings > Privacy & Security > Accessibility` |

Apple documents `AXIsProcessTrustedWithOptions` as returning whether the current process is a trusted accessibility client. Its prompt option informs the user asynchronously when the process is untrusted; the prompt does not change the function's return value. See [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions).

Apple Support describes Accessibility permission as the permission users grant when a third-party app tries to access and control the Mac through accessibility features. See [Allow accessibility apps to access your Mac](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac).

MVP implication:

- If double-Shift is detected but Accessibility is missing, show the setup panel
  instead of starting a broken selection.
- Explain that Input Monitoring recognizes the activation gesture and protects
  the bounded startup handoff by consuming only Arrow/Command-C/Escape, while
  Accessibility reads the caret and text positions after Grid mode starts.

## Sandbox and Distribution Implications

Apple's App Sandbox documentation says the sandbox limits access to resources requested through entitlements, and that Mac App Store distribution requires App Sandbox. See [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox), [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox), and [Distributing software on macOS](https://developer.apple.com/macos/distribution/).

Apple DTS describes `CGEventTap` with Input Monitoring as the sandbox-compatible
path for keyboard monitoring, while Apple documents `.defaultTap` as an active
filter. App Store, sandbox, and active-filter TCC viability still require end-to-
end validation; this document does not treat API availability as release evidence.

Pre-alpha recommendation:

| Track | Recommendation | Reason |
|---|---|---|
| Pre-alpha distribution | Developer ID signed and notarized, outside the Mac App Store | Faster iteration while validating Accessibility text extraction and overlay behavior; App Sandbox can be tested as a separate compatibility mode |
| Grid input implementation | Normally pass-through active `CGEventTap` with the bounded transition guard | Required for reliable double-Shift recognition and immediate source-safe commands; TCC onboarding/revocation/filtering must be validated |
| Accessibility text extraction | Validate both unsandboxed and sandboxed behavior in #6 / later implementation | Full AX access may be the gating factor for App Store viability |
| App Store path | Defer decision until AX extraction and overlay spikes are complete | The shortcut path is feasible either way; the complete GridSelect workflow may not be |

For non-App Store distribution, Apple recommends Developer ID signing and notarization so Gatekeeper can identify trusted software. See [Signing your apps for Gatekeeper](https://developer.apple.com/developer-id/).

## Missing-Permission Flow

Production requires independent Input Monitoring and Accessibility gates:

| State | Condition | User-visible behavior | App behavior |
|---|---|---|---|
| Ready | Input Monitoring and Accessibility granted; event tap active | Double-Shift starts Grid mode | Normal operation |
| Input setup needed | Input Monitoring missing | Status explains that Grid gestures cannot be observed and links to Input Monitoring | Do not create the event tap or overlay |
| Accessibility setup needed | Input Monitoring granted; Accessibility missing | A detected Grid gesture opens or highlights Accessibility guidance | Do not resolve caret/text or show a misleading selection |
| Input listener failed | Permission appears granted but event tap creation/enabling fails | Status shows Grid input inactive with Recheck guidance | Fail closed; do not fall back to a broad `NSEvent` monitor |
| Permission revoked | Either permission is revoked later | Identify the missing permission and show Recheck | Disable the event tap and clean up any active overlay without copying |

Avoid hiding all UI behind double-Shift. A menu bar/status item must remain
usable when either permission is missing or the event tap is inactive.

## Minimal Setup Copy

### Accessibility

Title: `Allow GridSelect to read text positions`

Body: `GridSelect needs Accessibility to find text in the app you select from. It uses this only after you start a selection.`

Steps:

1. `Open System Settings.`
2. `Go to Privacy & Security > Accessibility.`
3. `Turn on GridSelect.`
4. `Return to GridSelect and choose Recheck.`

### Input Monitoring

Title: `Enable Grid mode keyboard controls`

Body: `GridSelect needs Input Monitoring to notice double-Shift while you use another app. During the brief startup handoff it holds only Arrow, Command-C, or Escape so they cannot affect that app before Grid mode is ready. It does not store what you type, and ordinary input and Shift release pass through.`

Steps:

1. `Open System Settings.`
2. `Go to Privacy & Security > Input Monitoring.`
3. `Turn on GridSelect.`
4. `Return to GridSelect and choose Recheck.`

## Recommended MVP Permission Flow

1. Start as a menu bar or small agent-style app with a visible setup surface.
2. Explain Input Monitoring before requesting it from an explicit enable action.
3. Once granted, create the normally pass-through active event tap and surface creation, enablement, or filtering failure.
4. On a valid double-Shift gesture, check Accessibility before resolving the frontmost text caret or showing a keyboard-anchored selection.
5. If Accessibility is missing, request it only from an explicit setup action and show the Accessibility instructions.
6. Once both permissions are granted, use double-Shift only to enter Grid mode; capture caret geometry before the overlay takes local keyboard focus for Shift+Arrow, Command-C, and Escape.
7. Recheck both permissions on app activation and after setup actions; disable the listener and clean up active UI if either permission is revoked.

## On-Device Validation Plan

The original Carbon prototype remains historical evidence for issue #8. The
production path additionally requires a `CGEventTap` prototype or implementation
that confirms:

| Check | Expected result |
|---|---|
| Fresh install, no permissions granted | UI remains reachable; no listener or overlay is presented as ready |
| Request Input Monitoring | System prompt/path is accurate; denial leaves the listener inactive |
| Grant Input Monitoring | Double-Shift is recognized without consuming unrelated input |
| Double-Shift timing/state | One Shift press, a slow second press, or another intervening key does not enter Grid mode; the approved sequence does |
| Grid commands | After caret capture, overlay-local held Shift+Arrow adjusts; Shift release freezes; Command-C requests copy; Escape cancels; the source app receives none of these commands |
| Grant Accessibility | Keyboard entry resolves caret geometry in a supported text file |
| Revoke either permission | Active input/overlay is disabled and cleaned up without copying |
| Sandboxed and unsandboxed builds | Record actual end-to-end behavior separately; do not infer release viability from API availability |

## Historical Carbon Prototype

Issue #8 includes a minimal Carbon hot-key prototype at
`spikes/macos-shortcut/hotkey-prototype.swift`.

The prototype intentionally avoids third-party shortcut wrappers and validates
the raw Carbon permission surface. It uses `RegisterEventHotKey` for the
default `Command-Shift-G` shortcut, installs a Carbon hot-key event handler, and
updates a menu-bar status item when the shortcut fires. It also beeps and prints
an activation line to stdout so the visible action has both UI and terminal
evidence.

Run the prototype in an interactive macOS GUI session:

```sh
swift spikes/macos-shortcut/hotkey-prototype.swift
```

Expected behavior:

1. A `GridSelect HotKey` status item appears in the menu bar.
2. Pressing `Command-Shift-G` changes the menu-bar title to `GridSelect 1`,
   `GridSelect 2`, and so on.
3. The terminal prints a timestamped `Triggered N` line.
4. No Accessibility or Input Monitoring prompt appears for shortcut detection.
5. Choose `Quit` from the status-item menu to exit.

The prototype also has a non-interactive smoke test that registers and
unregisters the same hot key without entering the AppKit run loop:

```sh
swiftc spikes/macos-shortcut/hotkey-prototype.swift -o /tmp/gridselect-hotkey-prototype
/tmp/gridselect-hotkey-prototype --smoke-test
```

This does not prove the visible action path, but it proves the current host can
call `RegisterEventHotKey` for the default shortcut and receive `noErr`.

## Historical Prototype Validation Status

| Check | Result | Evidence |
|---|---|---|
| Prototype compile | Passed | `swiftc spikes/macos-shortcut/hotkey-prototype.swift -o /tmp/gridselect-hotkey-prototype` |
| Help output | Passed | `swift spikes/macos-shortcut/hotkey-prototype.swift --help` |
| Register/unregister smoke test | Passed | `/tmp/gridselect-hotkey-prototype --smoke-test` printed `smoke-test: registered and unregistered Command-Shift-G` |
| Visible menu-bar action | Not run in automated CLI | Requires an interactive macOS GUI session and manual `Command-Shift-G` input while the prototype keeps running. |
| TCC prompt observation | Not run in automated CLI | Confirm during the same manual GUI run that shortcut detection does not request Accessibility or Input Monitoring. |

If the historical prototype is rerun, copy this table into the task record or
issue comment. It does not count as production Grid-mode evidence:

| Field | Value |
|---|---|
| Date |  |
| macOS version |  |
| Prototype command | `swift spikes/macos-shortcut/hotkey-prototype.swift` |
| Default shortcut | `Command-Shift-G` |
| Status item appeared |  |
| Menu-bar title changed after shortcut |  |
| Stdout printed activation line |  |
| Accessibility prompt appeared |  |
| Input Monitoring prompt appeared |  |
| Registration failure OSStatus, if any |  |
| Notes |  |

## Open Follow-Ups

- Implement and run the active event-tap transition guard in an interactive GUI session;
  record Input Monitoring grant/missing/revoked, double-Shift recognition,
  unrelated-input pass-through, Grid commands, and cleanup evidence.
- Keep Carbon prototype results labeled historical; they do not satisfy the
  approved production activation criteria.
- #6 must validate whether the Accessibility text-extraction path is compatible with App Sandbox and Mac App Store expectations.
- #7 must validate overlay behavior in the same distribution modes.
- #16 owns separate Input Monitoring and Accessibility readiness/recovery UI.
- Track per-macOS-release changes to event-tap permission and modifier-event
  behavior as part of release QA.

## Sources

- Apple Developer Forums (Apple Frameworks Engineer): [RegisterEventHotKey behavior change on macOS Sequoia — intentional Shift/Option-only restriction, error -9868, ⌘/⌃ combos unaffected, 15.2 relaxation](https://developer.apple.com/forums/thread/763878)
- Apple Developer Forums (Apple DTS): [Global hotkey implementation options and TCC positioning](https://developer.apple.com/forums/thread/735223)
- Apple Developer Forums (Apple DTS): [CGEventTap + Input Monitoring for sandboxed keyboard monitoring](https://developer.apple.com/forums/thread/707680?answerId=716892022#716892022)
- Apple Developer Forums (Apple DTS): [Accessibility Permission In Sandbox For Keyboard](https://developer.apple.com/forums/thread/789896)
- Apple Developer Documentation: [CGEvent.tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/1454426-tapcreate)
- Apple Developer Documentation: [CGPreflightListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess%28%29)
- Apple Developer Documentation: [CGRequestListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess%28%29)
- Apple Developer Documentation: [IOHIDCheckAccess](https://developer.apple.com/documentation/iokit/3181573-iohidcheckaccess)
- Apple Developer Documentation: [IOHIDRequestAccess](https://developer.apple.com/documentation/iokit/3181574-iohidrequestaccess)
- Apple Developer Documentation: [NSEvent.addGlobalMonitorForEvents](https://developer.apple.com/documentation/appkit/nsevent/1535472-addglobalmonitorforevents)
- Apple Developer Documentation: [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- Apple Developer Documentation: [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- Apple Developer Documentation: [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- Apple Developer: [Distributing software on macOS](https://developer.apple.com/macos/distribution/)
- Apple Developer: [Signing your apps for Gatekeeper](https://developer.apple.com/developer-id/)
- Apple Support: [Control access to input monitoring on Mac](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac)
- Apple Support: [Allow accessibility apps to access your Mac](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac)
- Wrapper libraries: [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), [soffes/HotKey](https://github.com/soffes/HotKey)
- Note: `RegisterEventHotKey` is declared in `Carbon.HIToolbox` (Carbon Event Manager) and has no page in the current Apple documentation site; this documentation gap is recorded as a risk in the option matrix.
