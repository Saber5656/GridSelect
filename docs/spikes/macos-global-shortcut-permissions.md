# macOS Global Shortcut and Permission Flow Spike

Date: 2026-07-05

Issue: [#8 Spike global shortcut and permission flow on macOS](https://github.com/Saber5656/GridSelect/issues/8)

## Summary

Use Carbon hot-key registration (`RegisterEventHotKey` from `Carbon.HIToolbox`, ideally via a maintained Swift wrapper such as [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) or [soffes/HotKey](https://github.com/soffes/HotKey)) as the MVP global shortcut path.

In ADR 0001's terms ("choose the least invasive option", "avoid event taps unless the shortcut spike proves they are necessary", "avoid requesting … Input Monitoring unless a later decision proves they are necessary"):

- Hot-key registration requires **no TCC permission** — no Input Monitoring and no Accessibility.
- The app receives only the registered key combination. There is no key-stream visibility, so no key-logging capability exists and no privacy copy is needed for the shortcut itself.
- It works in sandboxed and Mac App Store apps and is the de-facto approach used by mainstream menu-bar utilities and wrapper libraries.
- The MVP already requires Accessibility for text extraction (#6). With hot-key registration, first-run onboarding needs exactly **one** sensitive permission instead of two.

Keep a listen-only `CGEventTap` + **Input Monitoring** design as the documented **fallback**, adopted only if on-device validation shows hot-key registration cannot serve the MVP (see trigger criteria below). **Accessibility** remains a separate permission gate for the later text-extraction path, not for shortcut detection.

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
| `RegisterEventHotKey` (Carbon HIToolbox), directly or via KeyboardShortcuts / HotKey wrappers | **None known** — no Input Monitoring, no Accessibility. macOS Sequoia 15.0 rejects combos whose only modifiers are Shift/Option (relaxed again in 15.2); combos including Command or Control are unaffected | Works in sandboxed and Mac App Store apps | Purpose-built hot-key registration; delivers only the registered combo (no key stream); least invasive; actively maintained Swift wrappers with recorder UI | Legacy Carbon lineage; Apple DTS discourages it for keyboard-*monitoring* use cases; no page in the current Apple doc system; per-OS behavior changes (Sequoia) must be tracked | **Use for MVP** — validate on-device |
| `CGEvent.tapCreate` / `CGEventTapCreate` listen-only event tap | Input Monitoring on modern macOS for listening to key events | Apple DTS states this is the sandbox-friendly path for keyboard *monitoring* and is available to Mac App Store apps | Official Core Graphics API, explicit preflight/request APIs, works when app is inactive, can observe combos hot keys cannot express (modifier-only, Fn) | Grants visibility of the full key stream — a sensitive permission with real onboarding cost; privacy wording and implementation discipline required; Swift callback/run-loop wiring is fiddly | **Fallback only** — adopt if hot-key registration proves insufficient |
| `NSEvent.addGlobalMonitorForEvents` | Accessibility for key-related events | Poorer fit; Apple DTS recommends `CGEventTap` instead for sandboxed keyboard monitoring | Simple AppKit API; good for quick local experiments | Can only observe, key events need Accessibility — the wrong permission for this job | Avoid for MVP shortcut |
| Local app shortcuts / SwiftUI commands | No global permission | App-only | Best UX when GridSelect is frontmost | Does not work globally | Use only for in-app commands |

## Primary Path: Hot-Key Registration

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
| macOS Sequoia modifier restriction | 15.0 intentionally rejects hot keys whose only modifiers are Shift and/or Option with `eventInternalErr` (-9868), as an anti-key-sniffing change; Apple relaxed Option/Option-Shift again in 15.2 beta. Combos including ⌘ or ⌃ are unaffected | Choose a default shortcut that includes ⌘ or ⌃; surface registration failure in the status UI |
| Registration failure / conflicts | `RegisterEventHotKey` returns a non-zero `OSStatus` when registration fails | Show a "shortcut inactive" state and let the user pick another combo (#16) |
| Expressiveness | Cannot express modifier-only (e.g. double-tap ⌘), Fn-based, or media-key activation | Acceptable for the MVP default; a hard requirement for these would trigger the fallback |
| DTS positioning | Apple DTS describes the API as legacy and recommends `CGEventTap` for keyboard *monitoring* | GridSelect needs activation, not monitoring; the least-invasive constraint in ADR 0001 wins. Revisit if Apple formally deprecates or breaks the API |

## Fallback Path: Listen-Only CGEventTap + Input Monitoring

Adopt only if one of these trigger criteria is met:

1. On-device validation shows hot-key registration cannot deliver a usable default shortcut on supported macOS versions.
2. The product later requires activation gestures hot keys cannot express (modifier-only, Fn-based).
3. Apple formally deprecates or disables Carbon hot-key registration.

If adopted, the listener should be a narrow, listen-only tap:

- Use `.cgSessionEventTap`, `.headInsertEventTap`, and `.listenOnly`.
- Listen for `.keyDown` and, if needed for modifier-only state, `.flagsChanged`.
- Match exactly one configured shortcut and return the original event unchanged.
- Do not log key values except a coarse "matched shortcut" diagnostic.
- If the tap returns `nil`, treat it as a missing permission or system denial and move the UI into a "shortcut inactive" state.

The event tap docs say `CGEvent.tapCreate` creates an event tap and returns `nil` if the tap cannot be created. Requested event types can be removed from the mask when monitoring is not permitted, and an empty mask causes creation to fail. See [CGEvent.tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/1454426-tapcreate).

Apple DTS recommends `CGEventTap` over `NSEvent` global monitors for sandboxed keyboard monitoring because the former uses Input Monitoring rather than Accessibility, with `CGPreflightListenEventAccess` and `CGRequestListenEventAccess` as the matching check/request APIs. See [Apple Developer Forums thread 707680](https://developer.apple.com/forums/thread/707680?answerId=716892022#716892022).

Input Monitoring specifics (fallback only):

| Need | API |
|---|---|
| Check whether the app can listen for input events | `CGPreflightListenEventAccess()` or `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` |
| Request the system prompt | `CGRequestListenEventAccess()` or `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` |
| User-facing settings location | `System Settings > Privacy & Security > Input Monitoring` |

Apple Support describes Input Monitoring as the permission that allows apps to monitor keyboard, mouse, or trackpad input while the user is using other apps. See [Control access to input monitoring on Mac](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac).

Fallback implementation notes:

- Request only after an explicit user action, such as "Enable Shortcut".
- Recheck on app activation and before starting the event tap.
- If the request returns `false` or the event tap still fails, show manual setup instructions and a "Recheck" action.
- Assume the system prompt is one-shot per app identity; keep the bundle identifier and signing identity stable during pre-alpha to reduce TCC reset churn.

## Accessibility

Do not require Accessibility to detect the global shortcut. Use it only when GridSelect needs to inspect other apps, such as text extraction via Accessibility APIs.

| Need | API / behavior |
|---|---|
| Check whether the process is trusted for Accessibility | `AXIsProcessTrusted()` |
| Request an Accessibility prompt | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)` |
| User-facing settings location | `System Settings > Privacy & Security > Accessibility` |

Apple documents `AXIsProcessTrustedWithOptions` as returning whether the current process is a trusted accessibility client. Its prompt option informs the user asynchronously when the process is untrusted; the prompt does not change the function's return value. See [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions).

Apple Support describes Accessibility permission as the permission users grant when a third-party app tries to access and control the Mac through accessibility features. See [Allow accessibility apps to access your Mac](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac).

MVP implication:

- If the global shortcut fires but Accessibility is missing, show the setup panel instead of starting a broken selection.
- Explain that Accessibility is for reading text positions from other apps after the user starts a selection.
- Do not imply the shortcut itself needs any permission.

## Sandbox and Distribution Implications

Apple's App Sandbox documentation says the sandbox limits access to resources requested through entitlements, and that Mac App Store distribution requires App Sandbox. See [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox), [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox), and [Distributing software on macOS](https://developer.apple.com/macos/distribution/).

Hot-key registration works inside App Sandbox and is used by Mac App Store apps, so the primary path does not constrain the distribution decision. Apple DTS's `CGEventTap`-over-`NSEvent` guidance applies to the fallback path only.

Pre-alpha recommendation:

| Track | Recommendation | Reason |
|---|---|---|
| Pre-alpha distribution | Developer ID signed and notarized, outside the Mac App Store | Faster iteration while validating Accessibility text extraction and overlay behavior; App Sandbox can be tested as a separate compatibility mode |
| Shortcut implementation | Hot-key registration via a maintained wrapper | No permission surface; sandbox-compatible; keeps the fallback design ready if validation fails |
| Accessibility text extraction | Validate both unsandboxed and sandboxed behavior in #6 / later implementation | Full AX access may be the gating factor for App Store viability |
| App Store path | Defer decision until AX extraction and overlay spikes are complete | The shortcut path is feasible either way; the complete GridSelect workflow may not be |

For non-App Store distribution, Apple recommends Developer ID signing and notarization so Gatekeeper can identify trusted software. See [Signing your apps for Gatekeeper](https://developer.apple.com/developer-id/).

## Missing-Permission Flow

Primary path — a single permission gate (Accessibility), plus shortcut-registration health:

| State | Condition | User-visible behavior | App behavior |
|---|---|---|---|
| Ready | Hot key registered; Accessibility granted | Shortcut starts selection mode | Normal operation |
| Selection setup needed | Hot key registered; Accessibility missing | Shortcut opens the setup panel | Do not start extraction; call `AXIsProcessTrustedWithOptions` only after an explicit user action |
| Shortcut inactive | Hot-key registration failed (conflict or OS restriction) | Status shows "shortcut inactive" with a change-shortcut affordance | Retry after the user picks another combo |
| Permission revoked | Accessibility revoked later | Inactive state and "Recheck" | Fail closed; no background retry loops |

If the fallback path is ever adopted, it adds the Input Monitoring gate ("Shortcut setup needed" / "Tap failed" states) from the fallback section above.

Avoid hiding all UI behind the global shortcut. A menu bar/status item must remain usable when the shortcut is inactive.

## Minimal Setup Copy

### Accessibility

Title: `Allow GridSelect to read text positions`

Body: `GridSelect needs Accessibility to find text in the app you select from. It uses this only after you start a selection.`

Steps:

1. `Open System Settings.`
2. `Go to Privacy & Security > Accessibility.`
3. `Turn on GridSelect.`
4. `Return to GridSelect and choose Recheck.`

### Input Monitoring (fallback path only)

Only needed if the CGEventTap fallback is adopted.

Title: `Enable the GridSelect shortcut`

Body: `GridSelect needs Input Monitoring to notice its shortcut while you are using other apps. It ignores other key presses and does not store what you type.`

Steps:

1. `Open System Settings.`
2. `Go to Privacy & Security > Input Monitoring.`
3. `Turn on GridSelect.`
4. `Return to GridSelect and choose Recheck.`

## Recommended MVP Permission Flow

1. Start as a menu bar or small agent-style app with a visible setup surface.
2. On launch, register the default hot key (no permission involved). Surface registration failure in the status UI with a change-shortcut affordance.
3. When the shortcut fires, check `AXIsProcessTrusted()` only if the next step needs Accessibility text extraction.
4. If Accessibility is missing, call `AXIsProcessTrustedWithOptions` from an explicit setup action and show the Accessibility instructions.
5. Once Accessibility is granted, start rectangular selection mode.
6. Recheck permissions on app activation and after setup actions.
7. Keep shortcut editing local-only and minimal for pre-alpha; do not build sync or full settings in this issue.

## On-Device Validation Plan

The original recommendation was desk research. Issue #8's acceptance criteria
also include a working prototype ("A prototype can trigger a visible action from
a global shortcut"), and the prototype/manual validation path below must
confirm:

| Check | Expected result |
|---|---|
| Fresh install, no permissions granted | Default ⌘-including hot key triggers a visible action with **no TCC prompt** |
| Shift/Option-only combo on macOS 15.0–15.1 | Registration fails cleanly (`-9868`) and the failure is surfaced, not silent |
| Conflicting combo (already registered elsewhere) | Failure surfaced; user can change the combo |
| Sandboxed build | Hot key still works |
| Unsandboxed Developer ID notarized build | Same flow; notarized build opens normally under Gatekeeper |
| Grant Accessibility after shortcut works | Shortcut proceeds into the selection/extraction path |
| Revoke Accessibility | Shortcut opens the setup panel instead of starting extraction |
| Fallback build (CGEventTap), if exercised | Input Monitoring grant/revoke cycle starts/stops the tap per the fallback plan |

## Prototype

Issue #8 now includes a minimal Carbon hot-key prototype at
`spikes/macos-shortcut/hotkey-prototype.swift`.

The prototype intentionally avoids third-party shortcut wrappers so the MVP can
validate the raw permission surface first. It uses `RegisterEventHotKey` for the
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

## Prototype Validation Status

| Check | Result | Evidence |
|---|---|---|
| Prototype compile | Passed | `swiftc spikes/macos-shortcut/hotkey-prototype.swift -o /tmp/gridselect-hotkey-prototype` |
| Help output | Passed | `swift spikes/macos-shortcut/hotkey-prototype.swift --help` |
| Register/unregister smoke test | Passed | `/tmp/gridselect-hotkey-prototype --smoke-test` printed `smoke-test: registered and unregistered Command-Shift-G` |
| Visible menu-bar action | Not run in automated CLI | Requires an interactive macOS GUI session and manual `Command-Shift-G` input while the prototype keeps running. |
| TCC prompt observation | Not run in automated CLI | Confirm during the same manual GUI run that shortcut detection does not request Accessibility or Input Monitoring. |

Manual validation should copy this table into the task record or issue comment:

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

- Run the shortcut prototype in an interactive GUI session and record visible-action evidence, no-TCC behavior, conflicts, and Sequoia-restriction checks.
- #6 must validate whether the Accessibility text-extraction path is compatible with App Sandbox and Mac App Store expectations.
- #7 must validate overlay behavior in the same distribution modes.
- #16 should own the eventual minimal settings/setup UI, including the change-shortcut affordance for registration failures.
- Track per-macOS-release changes to hot-key behavior (e.g. the Sequoia Shift/Option restriction and its 15.2 relaxation) as part of release QA.

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
