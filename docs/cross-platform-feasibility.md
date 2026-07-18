# Windows and Linux Rectangular-Selection Feasibility

| Field | Value |
|---|---|
| Issue | [#21](https://github.com/Saber5656/GridSelect/issues/21) |
| Status | Research complete; implementation not started |
| Evidence date | 2026-07-18 Asia/Tokyo (2026-07-17 UTC) |

## Purpose and Evidence Boundary

This note evaluates whether the macOS GridSelect interaction can later be
implemented on Windows and Linux. It covers global activation, overlay
placement, accessible text and caret geometry, clipboard output, and
permission, security, and packaging constraints.

This is desk research against official platform documentation, not runtime
proof. Statements labelled as risks or inferences require the spikes listed
below. This note does not approve a product interaction change, refactor the
current code, choose a cross-platform UI framework, add dependencies, or move
Windows or Linux into the macOS MVP.

Linux is evaluated as two different environments. Wayland and X11 do not offer
one interchangeable global-input or overlay contract, so a single generic
"Linux adapter" would hide the most important feasibility constraints.

## Decision Summary

| Target | Research verdict | Main reason | Recommendation |
|---|---|---|---|
| Windows desktop | Feasible enough for a native proof-of-concept; confidence is medium until live UI Automation and input-handoff tests pass. | Win32 exposes global input, top-level overlay, clipboard, and UI Automation contracts. The remaining uncertainty is provider quality and safe input handoff, rather than the absence of a platform primitive. | Investigate Windows next, after the macOS MVP proves the workflow. Start with a disposable native spike, not a shipping port. |
| Linux on Wayland | The current double-Shift plus absolute screen overlay interaction is not portably implementable from the documented cross-desktop contracts. | Focused clients receive normal keyboard events; the GlobalShortcuts portal models simple shortcuts, and GTK documents that Wayland has no global coordinate system for client window placement. | Do not promise parity yet. Obtain maintainer approval for a portal-compatible activation gesture, then prove a compositor-supported overlay and AT-SPI geometry path. |
| Linux on X11 | Technically plausible, but unsuitable as the architecture-setting first Linux target. | X11 supports passive key grabs/raw key observation and global window placement, but these carry shortcut conflicts, broad input visibility, window-manager variance, and do not solve Wayland. | Treat as a later compatibility adapter. Do not ship an X11-only port as evidence that Linux support is solved. |

The recommended post-macOS order is therefore **Windows, then a Wayland-first
Linux design spike, then an optional X11 compatibility adapter**. This order is
about technical risk, not market priority. Any product-scope or interaction
change still requires maintainer approval.

## Current macOS Baseline

The accepted [macOS MVP ADR](adr/0001-macos-native-mvp-architecture.md) and the
current source tree establish this baseline:

| Capability | Current macOS boundary | Cross-platform implication |
|---|---|---|
| Activation and guarded handoff | `MacOSGlobalShortcut` uses a narrow `CGEventTap` to detect double-Shift and briefly guard Arrow, Command-C, and Escape until the overlay owns input. | Other platforms need to preserve the behavioral invariants, but must use their own event and focus contracts. |
| Overlay | `MacOSSelectionOverlay` uses AppKit panels and macOS display/window ordering. | Window construction, stacking, focus, spaces/full-screen behavior, and coordinates remain platform-owned. |
| Text and caret access | `MacOSAccessibilitySelectionService` and `MacOSAccessibilityTextExtractor` use `AXUIElement`. | Windows UI Automation and Linux AT-SPI objects must not leak into the core model. |
| Clipboard | `MacOSPasteboardWriter` owns `NSPasteboard`; `ClipboardTextFormatter` owns plain-text formatting. | Formatting rules can be shared. Publishing the result is an adapter responsibility. |
| Permissions and status | The app explains Input Monitoring and Accessibility separately. | Windows integrity boundaries and Linux compositor/sandbox capabilities do not map to these two booleans; status and recovery must be platform-specific. |

The comparison target is the observable behavior and privacy boundary, not a
line-for-line translation of AppKit or ApplicationServices code.

## Capability Assessment

### 1. Global Activation and Input Handoff

#### Windows

[`RegisterHotKey`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey)
registers a system-wide modifier/virtual-key combination and delivers
`WM_HOTKEY`. That contract is appropriate for an ordinary chord, but it does
not provide the press/release sequence and bounded event-consumption handoff
required by double-Shift.

Two lower-level candidates require a spike:

| Candidate | Officially documented capability | Fit and risk |
|---|---|---|
| [Raw input registration](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerrawinputdevices) with [`RIDEV_INPUTSINK`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-rawinputdevice) | A target window can receive raw device input even when it is not foreground. Only one window per raw-input device class can be registered within a process. | Promising for normally passive idle detection, but it does not document the hook-style ability to consume guarded commands during overlay handoff. |
| [`WH_KEYBOARD_LL` / `LowLevelKeyboardProc`](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc) | Observes keyboard messages on the installing thread's message loop and may return nonzero to prevent an event reaching the rest of the hook chain or target window. | Can model the macOS transition guard, but the callback must be fast. Windows may silently remove a hook that exceeds its timeout, and Microsoft recommends raw input for many monitoring cases. |

The Windows spike should compare a raw-input idle listener plus a narrowly
enabled low-level hook against one always-installed, normally pass-through
low-level hook. It must prove that only Shift edges are inspected while idle,
that guarded key-down/key-up pairs cannot leak across focus transfer, and that
timeouts or focus failure cancel cleanly. The general [Windows hook
guidance](https://learn.microsoft.com/en-us/windows/win32/winmsg/about-hooks)
reinforces that hooks affect system performance and should be scoped narrowly.

This is not a recommendation to install a broad keylogger. Typed characters,
virtual-key traces, target identities, and timing histories must not be logged.

#### Linux on Wayland

The core Wayland [`wl_keyboard`
protocol](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_keyboard)
sends key events to the surface with keyboard focus. It is not a global
keyboard-listener interface.

The cross-desktop [GlobalShortcuts
portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html)
can activate a registered shortcut regardless of application focus and gives
the desktop control over binding and user confirmation. However, the companion
[shortcuts specification](https://specifications.freedesktop.org/shortcuts-spec/latest/)
is a draft for simple keyboard shortcuts expressed as modifiers plus one key.
The inference for GridSelect is that a sequential modifier-only double-tap is
not representable by this portable contract.

Recent AT-SPI exposes compositor-mediated [`AtspiDevice`
key grabs](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/method.Device.add_key_grab.html)
through [`AtspiDeviceA11yManager`](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/class.DeviceA11yManager.html).
This is a research candidate for legitimate assistive-technology integration,
not evidence of a cross-desktop general-shortcut contract. The older AT-SPI
[`DeviceEventListener`](https://gnome.pages.gitlab.gnome.org/at-spi2-core/devel-docs/doc-org.a11y.atspi.DeviceEventListener.html)
is explicitly legacy and unsupported on Wayland.

The portable Wayland direction therefore needs a maintainer-approved,
user-configurable portal chord. GridSelect must not silently replace
double-Shift, claim AT privileges merely to preserve it, or use device access as
a shortcut workaround.

#### Linux on X11

Xlib [`XGrabKey`](https://www.x.org/releases/current/doc/libX11/libX11/libX11.html#XGrabKey)
supports passive grabs, including a modifier key as the grabbed key; conflicting
grabs can fail with `BadAccess`. The [XInput 2
protocol](https://www.x.org/releases/current/doc/inputproto/XI2proto.txt) exposes
raw key press/release events selected on root windows, including delivery during
other clients' grabs in XI 2.1.

Those primitives can observe double-Shift, but they also expose broader global
input than the portal model. An X11 adapter would need a sparse, content-blind
filter, no input logging, explicit grab-conflict handling, and a bounded
handoff. XWayland does not turn these X11 client contracts into a portable
Wayland-global solution.

### 2. Overlay, Focus, and Screen Coordinates

#### Windows

Win32 documents the required building blocks: layered and topmost/no-activate
[extended window styles](https://learn.microsoft.com/en-us/windows/win32/winmsg/extended-window-styles),
alpha-composited [layered
windows](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features#layered-windows),
and [`SetWindowPos`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos)
with `HWND_TOPMOST`. This makes a transparent rectangular overlay plausible.

It is not yet proof of GridSelect's focus handoff. `WS_EX_NOACTIVATE` and an
interactive keyboard overlay have different goals, topmost only defines a
window-order class, and foreground activation is constrained by
[`SetForegroundWindow`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow).
The spike must test a non-activating presentation followed by explicit ownership
of Grid commands, multi-monitor negative coordinates, per-monitor DPI, and
full-screen apps. Microsoft documents DPI virtualization and per-monitor
awareness in its [high-DPI desktop application
guidance](https://learn.microsoft.com/en-us/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows).
Secure desktop is explicitly unsupported.

#### Linux on Wayland

GTK's [`gtk_window_get_position`
documentation](https://docs.gtk.org/gtk3/method.Window.get_position.html)
states that Wayland does not have a global coordinate system and returns
`(0, 0)`. [`gtk_window_move`](https://docs.gtk.org/gtk3/method.Window.move.html)
also only asks a window manager to move a window, which it may ignore.

Therefore a normal portable client cannot position an independent transparent
surface over an arbitrary rectangle in another application's global screen
space. A compositor-specific shell protocol, desktop component, or a materially
different interaction would be needed. That is the largest Linux architecture
blocker and must be solved before choosing a toolkit or packaging format.

#### Linux on X11

X11 exposes global window coordinates and placement, so an overlay is
technically possible. The EWMH [`_NET_WM_STATE_ABOVE`
contract](https://specifications.freedesktop.org/wm/latest-single/#STACKINGORDER)
places a window above most windows, but the documented stacking order allows a
focused full-screen window above it. ICCCM warns that
[`override-redirect`](https://www.x.org/releases/current/doc/xorg-docs/icccm/icccm.html#Pop_up_Windows)
windows bypass normal window-manager policy and should be used cautiously.

The X11 spike must therefore cover common window managers, full-screen apps,
focus transfer, multiple monitors, and scale changes. A result on one desktop
environment is not a cross-desktop guarantee.

### 3. Accessible Text and Caret Geometry

#### Windows UI Automation

UI Automation is a provider/client cross-process system, documented in the
[UI Automation fundamentals](https://learn.microsoft.com/en-us/windows/win32/winauto/entry-uiautocore-overview).
The [`TextPattern` and `TextRange`
contracts](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-about-text-and-textrange-patterns)
cover text, ranges, movement, and visible geometry. Providers are only required
to support `Character` and `Document` text units and may promote unsupported
units, so the adapter cannot assume uniform line/word behavior.

The strongest caret path is
[`IUIAutomationTextPattern2::GetCaretRange`](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomationtextpattern2-getcaretrange),
which returns an active flag and a degenerate range at the caret. Nearby range
discovery is available through
[`RangeFromPoint`](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomationtextpattern-rangefrompoint).
There is an important documentation tension: the caret-range page says the
range can be used to find a caret bounding rectangle, while
[`GetBoundingRectangles`](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomationtextrange-getboundingrectangles)
documents an empty array for a degenerate range. The spike must measure actual
providers and define a fail-closed derivation, such as a validated neighboring
character edge, rather than assuming caret geometry exists.

Cross-process range calls should be batched and budgeted. A fixture matrix must
include native controls, terminals, Electron-based editors, and browser text;
unsupported or virtualized providers are compatibility gaps, not permission
bypasses. Elements whose [`IsPassword`
property](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-automation-element-propids)
is true must never create a selection or clipboard path.

#### Linux AT-SPI

The current [`AtspiText`
interface](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/iface.Text.html)
exposes text, caret offset, character and range extents, point-to-offset mapping,
and bounded ranges. Coordinate values distinguish screen, window, and parent
space through [`AtspiCoordType`](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/enum.CoordType.html).
That interface is conceptually promising, but the enum and method surface alone
does not prove usable screen geometry. For example, the current GTK 4
[`gtkatspitext.c` provider](https://gitlab.gnome.org/GNOME/gtk/-/blob/0de20adcf206d7e26396a16660ea6ebe76d13091/gtk/a11y/gtkatspitext.c)
rejects `ATSPI_COORD_TYPE_SCREEN` for point and character/range extent queries
and reports bounded ranges as unsupported. On Wayland, an adapter would then
need to correlate parent- or window-relative text extents with compositor-owned
surface geometry even though normal clients do not have a global coordinate
system. This couples AT-SPI feasibility to the unresolved overlay protocol and
must be proven rather than inferred.

Actual feasibility depends on each toolkit/application provider. The AT-SPI
documentation lists [toolkit
implementations](https://gnome.pages.gitlab.gnome.org/at-spi2-core/devel-docs/toolkits.html),
while Ubuntu's official [accessibility-stack
overview](https://documentation.ubuntu.com/desktop/en/latest/explanation/accessibility-stack/)
notes that non-GTK toolkits must implement AT-SPI and that compatibility can
vary. Tests must cover GTK, Qt, browser, Electron, and terminal fixtures on both
Wayland and X11, especially a caret at the end of a line, wrapped text,
virtualized content, and multi-byte text. An
[`ATSPI_ROLE_PASSWORD_TEXT`](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/enum.Role.html)
source must fail closed.

UI Automation ranges, AT-SPI offsets, and macOS AX ranges remain adapter-private.
The core should receive validated visual rows, rectangles/boundaries, text, and
opaque source/session identities. It should not compare raw platform offsets or
own COM/D-Bus/accessibility handles.

### 4. Clipboard

#### Windows

The Win32 clipboard path is straightforward: open the clipboard, publish
`CF_UNICODETEXT`, and transfer ownership through
[`SetClipboardData`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setclipboarddata).
The documented [standard clipboard
formats](https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats)
include Unicode text. The adapter should write only after the user's Grid copy
command and should neither enumerate nor read clipboard history. Core newline,
row-order, and empty-selection rules remain in `ClipboardTextFormatter`.

Avoiding history reads does not prevent Windows itself from retaining the
published value in local clipboard history or synchronizing it through cloud
clipboard. Microsoft documents registered formats that can exclude content
from monitor processing, local history, or cloud upload on the same [clipboard
formats](https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats)
page. Preserving normal Windows clipboard behavior versus suppressing one or
both retention paths is an unresolved product and privacy decision. The native
spike must test the default path and the registered exclusion formats, including
interoperability with ordinary paste targets, before an implementation policy
is approved.

#### Linux

GDK exposes [`gdk_clipboard_set_text`](https://docs.gtk.org/gdk4/class.Clipboard.html)
as a toolkit-level publisher. On Wayland, the underlying
[`wl_data_device.set_selection`](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_data_device)
uses an input-event serial and delivers selection offers according to keyboard
focus. The likely path is feasible when GridSelect's interactive surface owns
focus and receives the explicit copy command, but this must be tested together
with the unresolved overlay/focus design.

On X11, the ICCCM [selection
model](https://www.x.org/releases/current/doc/xorg-docs/icccm/icccm.html#Acquiring_Selection_Ownership)
makes the client an owner that responds to conversion requests; a toolkit and
clipboard manager normally handle that lifetime. The xdg-desktop-portal
[`Clipboard`](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Clipboard.html)
interface is not a general fallback: it is tied to an existing RemoteDesktop or
InputCapture session. GridSelect should not open one merely to copy text.

### 5. Permission, Security, and Packaging Constraints

| Target | Constraint | Required product boundary |
|---|---|---|
| Windows | A normal medium-integrity UI Automation client cannot inspect elevated-process UI. Microsoft's [UI Automation security overview](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-securityoverview) limits `uiAccess` to signed assistive technology installed in a secure location and still excludes SYSTEM/secure desktop. | Run the first spike and proposed MVP at normal integrity. Mark elevated sources and secure desktop unsupported. Do not request `uiAccess` to obtain broader reach. |
| Windows | MSIX packages must be signed with a trusted certificate; Microsoft documents Store and non-Store [code-signing options](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options) and the [MSIX signing requirement](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview). | Use an unpackaged development harness for the feasibility spike. Choose Store/MSIX or another signed distribution path only after the input/UIA proof passes. |
| Wayland | Normal clients receive focused input and cannot use global placement. Portal shortcut binding is desktop-mediated and may involve user configuration. | Expose the actual backend capability instead of a fake macOS-style permission boolean. No `/dev/input`, RemoteDesktop/InputCapture, or broad AT privilege workaround. |
| X11 | Global key and screen/window primitives are broadly available to connected clients and grabs can conflict. | Minimize observed data, never log raw input/content, fail closed on conflicts, and explain the security surface. |
| Flatpak | The default sandbox limits host, device, display-socket, and D-Bus access; the official [sandbox-permissions guidance](https://docs.flatpak.org/en/latest/sandbox-permissions.html) recommends portals and warns against broad permissions. | Defer a Flatpak manifest until the Wayland shortcut, overlay, and AT-SPI design exists. Request only the minimum proven permissions; do not use full session-bus or input-device access as a shortcut. |
| Native Linux packages | Avoiding a sandbox does not create missing Wayland protocols and increases distro/distribution maintenance. | Packaging cannot be the workaround for the Wayland interaction gap. Choose formats only after the runtime architecture is proven. |

## Reuse Boundary

Cross-platform work should share behavior and fixtures before it tries to share
platform runtime code.

| Boundary | Reuse decision | Examples and required treatment |
|---|---|---|
| Pure selection and formatting rules | Share directly where current types remain platform-neutral. | `TextGrid`, `ClipboardTextFormatter`, row/column slicing, rectangle normalization, half-open column semantics, inclusive row semantics, frozen selection rules, generation/stale-result rejection, single-flight copy, fixed budgets, and failure taxonomy. Reuse their test fixtures across adapters. |
| Activation lifecycle semantics | Share the state-machine meaning, conditionally. | Double-tap timing, bounded queue, cancellation, and semantic Arrow/copy/Escape effects can be shared by Windows/X11 adapters that supply trusted edge/timestamp events. A Wayland portal chord may enter the lifecycle after recognition and bypass the double-tap recognizer. |
| Geometry semantics | Share only after a neutral boundary is defined from evidence. | `ScreenRectangle`, grid cells, and normalized visual rows are useful. Current `DisplayGeometry.appKitFrame`, `coreGraphicsBounds`, bottom-left AppKit assumptions, and viewport comments are macOS-specific and must not become a Windows/Linux API by renaming them mechanically. |
| User-visible command/status semantics | Share concepts, not current labels. | `commandC`, the two macOS permission booleans, and macOS recovery text need platform-neutral semantic commands and platform-owned capability/status presentation if a later refactor is approved. |
| OS objects and runtime operations | Never share across adapters. | `CGEventTap`, `NSPanel`, `AXUIElement`, `NSPasteboard`, Win32 messages/hooks/HWND/UIA COM objects, AT-SPI D-Bus objects, X11 IDs, Wayland surfaces/tokens, clipboard handles, platform offsets, focus, and packaging/signing code. |

No refactor is justified by this research alone. The macOS MVP should continue
to expose real implementation pressure first. A later design proposal can use
the table above to carve a smaller portable core without weakening macOS.

## Risks and Validation Gates

| Priority | Risk or unknown | Minimum evidence before implementation approval |
|---|---|---|
| P0 | Windows low-level monitoring may lose hooks, leak a guarded release, or interfere with other apps. | A native harness comparing raw input and `WH_KEYBOARD_LL`; automated state-machine traces plus manual focus/timeout/repeat/grab-conflict checks; logs audited to contain no input data. |
| P0 | Windows UIA caret geometry is absent or inconsistent across providers, including the degenerate-range contradiction. | A results table for native editor, terminal, Electron editor, and browser fixtures; caret-at-start/end, wrapped/virtualized text, DPI, and obscured/off-screen cases; explicit unsupported outcomes. |
| P0 | A portable Wayland overlay cannot be placed over source geometry. | A maintainer-reviewed prototype on at least GNOME and KDE using only supportable protocols, or an approved interaction redesign that does not require global placement. |
| P0 | The GlobalShortcuts portal cannot preserve double-Shift. | Maintainer approval of a configurable chord; portal binding/activation tests on GNOME and KDE; documented behavior when the portal/backend is unavailable. |
| P0 | A Wayland AT-SPI provider may expose only parent/window-relative extents, omit bounded ranges, and provide no portable way to correlate them with the overlay. | GTK, Qt, browser, Electron, and terminal probes on GNOME and KDE that record supported coordinate types and prove a source-scoped mapping into the chosen overlay geometry, or return an explicit unsupported result. |
| P0 | Secure/password/elevated content could enter extraction or clipboard paths. | Fixture tests that fail closed for Windows `IsPassword`, elevated/secure desktop boundaries, AT-SPI password roles, source identity changes, and permission/backend loss before and during copy. |
| P1 | Windows and X11 overlays lose focus, ordering, or coordinate correctness across displays/full-screen. | Multi-monitor, mixed-DPI/scale, negative-origin, full-screen, workspace, source-destroyed, and focus-race matrices with screenshots or structured observations. |
| P1 | Windows clipboard output may enter local history or cloud sync without an explicit retention policy. | Approve whether normal history/cloud behavior is preserved or suppressed; test the default and documented exclusion formats, ordinary paste interoperability, and the resulting privacy disclosure. |
| P1 | AT-SPI text/range/coordinate quality differs by toolkit and desktop session. | GTK, Qt, terminal, browser, and Electron fixtures on Wayland and X11; batched-call latency and resource limits; exact text/rectangle expected results. |
| P1 | Wayland clipboard publishing fails without a suitable input serial/focus owner. | Copy tests from the chosen overlay interaction on GNOME and KDE, including app exit and clipboard-manager behavior. |
| P2 | Packaging changes capabilities or creates excessive security prompts/permissions. | Repeat the passing harness under the candidate signed Windows package and candidate Linux sandbox; audit manifests and explain every capability. |

No platform reaches MVP status from API availability alone. Each gate needs
recorded expected/actual results, OS/desktop versions, provider application,
failure classification, and privacy review.

## Recommended Delivery Sequence

1. Finish and validate the macOS MVP so the observable workflow and reusable
   invariants are based on a working product.
2. Build an **unpackaged Windows native spike** containing only: double-Shift
   monitoring/handoff, a transparent interactive overlay, UIA text/caret
   fixtures, and explicit Unicode clipboard copy. Do not modify shared core
   architecture merely to make the spike compile.
3. If all Windows P0 gates pass, write a Windows architecture decision that
   chooses the input strategy, neutral core boundary, target-app support matrix,
   normal-integrity limitation, and distribution/signing path. Only then scope
   a Windows MVP.
4. Separately run a **Wayland-first Linux design spike**. First obtain approval
   for a portal-compatible activation chord, then prove overlay/focus, AT-SPI,
   and clipboard on GNOME and KDE. Do not start from X11 APIs and retrofit
   Wayland later.
5. If the Wayland design passes, define a Linux backend boundary and add X11 as
   an optional compatibility adapter with its own privacy and window-manager
   test matrix.

## Explicit Non-Decisions

- Windows and Linux remain post-MVP scope.
- This note does not select Swift, Rust, C++, .NET, GTK, Qt, Tauri, Electron, or
  any other language/runtime for a port.
- It does not approve replacing double-Shift on Linux; it identifies that as a
  required product decision.
- It does not choose whether a future Windows adapter preserves or suppresses
  local clipboard history and cloud clipboard synchronization.
- It does not approve Windows `uiAccess`, Linux input-device access, a full
  session-bus permission, RemoteDesktop/InputCapture portals, OCR, or screenshot
  extraction as compatibility workarounds.
- It does not choose MSIX, Microsoft Store, Flatpak, AppImage, distro-native
  packages, or another distribution channel.
- It does not promise support for elevated Windows apps, secure desktop,
  password fields, unsupported accessibility providers, exclusive full-screen
  surfaces, or every Linux desktop/compositor.
- It does not authorize implementation, refactoring, or dependency additions.

## Acceptance Criteria Mapping

| Issue #21 criterion | Research evidence |
|---|---|
| Global shortcut/double-Shift monitoring is evaluated. | Windows `RegisterHotKey`, raw input, and low-level hooks; Wayland keyboard/GlobalShortcuts/AT-SPI limits; X11 grabs and XI2 raw events. |
| Overlay feasibility is evaluated. | Win32 layered/topmost/DPI/focus contracts; Wayland global-coordinate blocker; X11 EWMH/ICCCM caveats. |
| Text accessibility and caret geometry are evaluated. | UIA TextPattern2/TextRange contradiction and provider matrix; AT-SPI Text/coordinate/toolkit matrix. |
| Clipboard feasibility is evaluated. | Win32 Unicode clipboard; GDK plus Wayland and X11 ownership/focus constraints; portal limitation. |
| Permissions, security, and packaging are evaluated. | Windows integrity/`uiAccess`/signing boundaries; Wayland/X11 capability split; Flatpak minimum-permission boundary. |
| Shared core and platform adapters are identified. | The reuse-boundary table separates pure rules, conditional semantics, geometry debt, UI semantics, and OS-owned objects. |
| Risks and next platform/order are recommended. | The risk gates and delivery sequence recommend Windows, then Wayland-first Linux, then optional X11. |
