# macOS Global Shortcut and Permission Flow Spike

Date: 2026-07-05

Issue: [#8 Spike global shortcut and permission flow on macOS](https://github.com/Saber5656/GridSelect/issues/8)

## Summary

Use a listen-only Core Graphics event tap (`CGEvent.tapCreate` / `CGEventTapCreate`) for the MVP global shortcut, and request **Input Monitoring** only when the user enables the shortcut. Keep **Accessibility** as a separate permission gate for the later text-extraction path, not for the shortcut listener itself.

For the pre-alpha, prefer Developer ID distribution outside the Mac App Store while the Accessibility text-extraction and overlay spikes are still being validated. Keep the shortcut implementation compatible with App Sandbox by avoiding `NSEvent.addGlobalMonitorForEvents` for key events and using the Input Monitoring APIs tied to `CGEventTap`.

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
| `CGEvent.tapCreate` / `CGEventTapCreate` listen-only event tap | Input Monitoring on modern macOS for listening to key events; legacy docs still mention assistive-device access for key events | Apple DTS states this is the better sandbox-friendly path for keyboard monitoring and is available to Mac App Store apps | Official Core Graphics API, explicit preflight/request APIs, works when app is inactive, can stay listen-only | Swift callback/run loop wiring is fiddly; privacy wording must be careful because Input Monitoring is sensitive | **Use for MVP** |
| `NSEvent.addGlobalMonitorForEvents` | Accessibility for key-related events | Poorer fit; Apple DTS recommends `CGEventTap` instead for sandboxed keyboard monitoring | Simple AppKit API; good for quick local experiments | Can only observe, cannot prevent/modify events, does not receive events sent to own app, key events need Accessibility | Avoid for MVP shortcut |
| `RegisterEventHotKey` / Carbon hot key APIs | Historically used for global hotkeys; current TCC story is less clear | Legacy Carbon toolbox; not a good long-term foundation | Purpose-built hotkey registration, widely used historically | Harder to justify for a new Swift app, weaker current documentation, Carbon coupling | Keep as fallback research only |
| Local app shortcuts / SwiftUI commands | No global permission | App-only | Best UX when GridSelect is frontmost | Does not work globally | Use only for in-app commands |

## Event Tap Design

The MVP listener should be a narrow, listen-only tap:

- Use `.cgSessionEventTap`, `.headInsertEventTap`, and `.listenOnly`.
- Listen for `.keyDown` and, if needed for modifier-only state, `.flagsChanged`.
- Match exactly one default shortcut.
- Return the original event unchanged.
- Do not log key values except a coarse "matched shortcut" diagnostic.
- If the tap returns `nil`, treat it as a missing permission or system denial and move the UI into a "shortcut inactive" state.

The event tap docs say `CGEvent.tapCreate` creates an event tap and returns `nil` if the tap cannot be created. The docs also note that requested event types can be removed from the mask when monitoring is not permitted, and an empty mask causes creation to fail. See [CGEvent.tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/1454426-tapcreate).

Apple DTS recommends `CGEventTap` over `NSEvent` global monitors for sandboxed keyboard monitoring because the former uses Input Monitoring rather than Accessibility. The same DTS answer points to `CGPreflightListenEventAccess` and `CGRequestListenEventAccess` as the matching check/request APIs. See [Apple Developer Forums thread 707680](https://developer.apple.com/forums/thread/707680?answerId=716892022#716892022).

## Input Monitoring

Use Input Monitoring for the shortcut listener.

| Need | API |
|---|---|
| Check whether the app can listen for input events | `CGPreflightListenEventAccess()` or `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` |
| Request the system prompt | `CGRequestListenEventAccess()` or `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` |
| User-facing settings location | `System Settings > Privacy & Security > Input Monitoring` |

Apple Support describes Input Monitoring as the permission that allows apps to monitor keyboard, mouse, or trackpad input while the user is using other apps. It also names the settings path as `Privacy & Security > Input Monitoring`. See [Control access to input monitoring on Mac](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac).

Implementation notes:

- Request only after an explicit user action, such as "Enable Shortcut".
- Recheck on app activation and before starting the event tap.
- If the request returns `false` or the event tap still fails, show manual setup instructions and a "Recheck" action.
- Assume the system prompt is one-shot per app identity; users may need to enable the app manually after denial or revocation.
- Keep the bundle identifier and signing identity stable during pre-alpha to reduce TCC reset churn.

## Accessibility

Do not require Accessibility just to detect the global shortcut. Use it only when GridSelect needs to inspect or interact with other apps, such as text extraction via Accessibility APIs.

| Need | API / behavior |
|---|---|
| Check whether the process is trusted for Accessibility | `AXIsProcessTrusted()` |
| Request an Accessibility prompt | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true] as CFDictionary)` |
| User-facing settings location | `System Settings > Privacy & Security > Accessibility` |

Apple documents `AXIsProcessTrustedWithOptions` as returning whether the current process is a trusted accessibility client. Its prompt option informs the user asynchronously when the process is untrusted; the prompt does not change the function's return value. See [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions).

Apple Support describes Accessibility permission as the permission users grant when a third-party app tries to access and control the Mac through accessibility features. It names the manual path as `Privacy & Security > Accessibility`. See [Allow accessibility apps to access your Mac](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac).

MVP implication:

- If the global shortcut fires but Accessibility is missing, show the setup panel instead of starting a broken selection.
- Explain that Accessibility is for reading text positions from other apps after the user starts a selection.
- Do not imply the shortcut itself needs Accessibility.

## Sandbox and Distribution Implications

Apple's App Sandbox documentation says the sandbox limits access to resources requested through entitlements, and that Mac App Store distribution requires App Sandbox. Apple's macOS distribution page lists App Sandbox as required for Mac App Store distribution and recommended outside the Mac App Store. See [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox), [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox), and [Distributing software on macOS](https://developer.apple.com/macos/distribution/).

Apple DTS guidance is useful for this spike:

- General Accessibility APIs are harder in sandboxed apps.
- Keyboard monitoring should use `CGEventTap` and Input Monitoring, not an `NSEvent` global event monitor and Accessibility.
- Some older Mac App Store examples may not prove sandbox feasibility because not all Mac App Store apps are sandboxed.

Pre-alpha recommendation:

| Track | Recommendation | Reason |
|---|---|---|
| Pre-alpha distribution | Developer ID signed and notarized, outside the Mac App Store | Faster iteration while validating Accessibility text extraction and overlay behavior; App Sandbox can be tested as a separate compatibility mode |
| Shortcut implementation | Build as if sandboxed: `CGEventTap` + Input Monitoring | Keeps the shortcut path aligned with current Apple DTS guidance |
| Accessibility text extraction | Validate both unsandboxed and sandboxed behavior in #6 / later implementation | Full AX access may be the gating factor for App Store viability |
| App Store path | Defer decision until AX extraction and overlay spikes are complete | Shortcut alone looks feasible; the complete GridSelect workflow may not be |

For non-App Store distribution, Apple recommends Developer ID signing and notarization so Gatekeeper can identify trusted software. See [Signing your apps for Gatekeeper](https://developer.apple.com/developer-id/).

## Missing-Permission Flow

Use a two-permission state machine:

| State | Condition | User-visible behavior | App behavior |
|---|---|---|---|
| Ready | Input Monitoring granted; Accessibility granted when extraction is needed | Shortcut works; selection can start | Event tap running |
| Shortcut setup needed | Input Monitoring missing | Menu/status item shows "Enable Shortcut" | Do not install event tap; call request API only after user action |
| Selection setup needed | Shortcut is available but Accessibility is missing | Shortcut opens setup panel | Do not start extraction; call `AXIsProcessTrustedWithOptions` after user action |
| Permission revoked | Previously granted permission is now missing | Show inactive state and "Recheck" | Stop tap or fail closed; no background retry loops |
| Tap failed | Preflight says allowed but `CGEventTap` returns `nil` | Show manual setup + troubleshooting | Log coarse failure; offer recheck |

Avoid hiding all UI behind the global shortcut. A menu bar/status item must remain usable when the shortcut is inactive.

## Minimal Setup Copy

Use short, specific copy. Avoid broad claims about reading all keyboard input.

### Input Monitoring

Title: `Enable the GridSelect shortcut`

Body: `GridSelect needs Input Monitoring to notice its shortcut while you are using other apps. It ignores other key presses and does not store what you type.`

Steps:

1. `Open System Settings.`
2. `Go to Privacy & Security > Input Monitoring.`
3. `Turn on GridSelect.`
4. `Return to GridSelect and choose Recheck.`

### Accessibility

Title: `Allow GridSelect to read text positions`

Body: `GridSelect needs Accessibility to find text in the app you select from. It uses this only after you start a selection.`

Steps:

1. `Open System Settings.`
2. `Go to Privacy & Security > Accessibility.`
3. `Turn on GridSelect.`
4. `Return to GridSelect and choose Recheck.`

## Recommended MVP Permission Flow

1. Start as a menu bar or small agent-style app with a visible setup surface.
2. On launch, run `CGPreflightListenEventAccess()`.
3. If Input Monitoring is missing, show "Enable Shortcut" and do not install the event tap.
4. When the user chooses "Enable Shortcut", call `CGRequestListenEventAccess()` and show the Input Monitoring instructions plus "Recheck".
5. After Input Monitoring is granted, create a listen-only `CGEventTap` for the default shortcut.
6. When the shortcut fires, check `AXIsProcessTrusted()` only if the next step needs Accessibility text extraction.
7. If Accessibility is missing, call `AXIsProcessTrustedWithOptions` from an explicit setup action and show the Accessibility instructions.
8. Once both gates required for the action are satisfied, start rectangular selection mode.
9. Recheck permissions on app activation, after setup actions, and after event-tap creation failures.
10. Keep shortcut editing local-only and minimal for pre-alpha; do not build sync or full settings in this issue.

## Validation Plan

Manual validation when an app target exists:

| Check | Expected result |
|---|---|
| Fresh install, no permissions | Setup UI appears; no event tap runs |
| Grant Input Monitoring | Event tap starts and shortcut triggers a visible action |
| Revoke Input Monitoring | Shortcut becomes inactive after recheck or tap failure |
| Grant Accessibility after shortcut setup | Shortcut can proceed into selection/extraction path |
| Revoke Accessibility | Shortcut opens setup panel instead of starting extraction |
| Sandbox build with `CGEventTap` | Shortcut path still works after Input Monitoring |
| Unsandboxed Developer ID build | Same TCC flow; notarized build opens normally under Gatekeeper |

## Open Follow-Ups

- #6 must validate whether the Accessibility text-extraction path is compatible with App Sandbox and Mac App Store expectations.
- #7 must validate overlay behavior in the same distribution modes.
- #16 should own the eventual minimal settings/setup UI.
- A future implementation issue should add the actual event tap wrapper and a tiny visible-action smoke test once the app scaffold exists.

## Sources

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
- Apple Developer Forums / Apple DTS: [Accessibility permission in sandboxed app](https://developer.apple.com/forums/thread/707680?answerId=716892022#716892022)
- Apple Developer Forums / Apple DTS: [Accessibility Permission In Sandbox For Keyboard](https://developer.apple.com/forums/thread/789896)
