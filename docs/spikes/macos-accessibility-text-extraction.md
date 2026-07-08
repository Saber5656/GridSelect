# macOS Accessibility Text Extraction Spike

Issue: [#6](https://github.com/Saber5656/GridSelect/issues/6)
Date: 2026-07-05
Status: Desk research complete; live fixture validation blocked until Accessibility permission can be granted to the probe host
Scope: Read-only macOS Accessibility API text extraction for rectangular text regions

## Conclusion

Based on the documented API surface, a no-OCR macOS MVP is expected to be feasible for monospace rectangular text regions, but only as a capability-gated Accessibility API path, not as a universal screen-text extractor.

This is a desk-research conclusion. The bundled probe could not query live app trees in the spike environment (`accessibilityTrusted: false`), so no target application has produced a supported/partial/unsupported measurement yet. Issue #6's acceptance criteria require testing at least three target app categories; the final feasibility call stays open until the manual fixture procedure below has been run with Accessibility permission granted.

The practical MVP should target focused or hit-tested text elements that expose all of the following:

| Requirement | Accessibility surface |
|---|---|
| Text content by character range | `kAXStringForRangeParameterizedAttribute` |
| A visible or bounded text range | `kAXVisibleCharacterRangeAttribute`, `kAXNumberOfCharactersAttribute`, or equivalent app-specific range |
| Bounds for text ranges | `kAXBoundsForRangeParameterizedAttribute` |
| Line mapping | `kAXLineForIndexParameterizedAttribute` and `kAXRangeForLineParameterizedAttribute`, or a fallback per-character bounds scan |

When those capabilities are present, GridSelect can map a screen rectangle to visible text rows and columns without OCR. When an app exposes only an accessibility label, only a full text value, a web/canvas rendering, or no range geometry, the MVP should report the target as unsupported rather than falling back to screenshots or image analysis.

## Explicit Non-Goals

- OCR, screenshots, PDF parsing, and image analysis.
- Modifying native selections in target applications.
- Promising extraction from every macOS app.
- Shipping production extraction code in this spike.

## Primary Sources

| Topic | Source |
|---|---|
| System-wide Accessibility object | [AXUIElementCreateSystemWide](https://developer.apple.com/documentation/applicationservices/1462095-axuielementcreatesystemwide) |
| Application Accessibility object | [AXUIElementCreateApplication](https://developer.apple.com/documentation/applicationservices/1459374-axuielementcreateapplication) |
| Attribute reads | [AXUIElementCopyAttributeValue](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue) |
| Attribute discovery | [AXUIElementCopyAttributeNames](https://developer.apple.com/documentation/applicationservices/1459475-axuielementcopyattributenames) |
| Parameterized attribute discovery | [AXUIElementCopyParameterizedAttributeNames](https://developer.apple.com/documentation/applicationservices/1458783-axuielementcopyparameterizedattr) |
| Parameterized attribute reads | [AXUIElementCopyParameterizedAttributeValue](https://developer.apple.com/documentation/applicationservices/1461203-axuielementcopyparameterizedattr) |
| Hit-testing by screen position | [AXUIElementCopyElementAtPosition](https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition) |
| Accessibility trust check | [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) |
| Permission prompt option | [kAXTrustedCheckOptionPrompt](https://developer.apple.com/documentation/applicationservices/kaxtrustedcheckoptionprompt) |
| Focused element | [kAXFocusedUIElementAttribute](https://developer.apple.com/documentation/applicationservices/kaxfocuseduielementattribute) |
| Element role | [kAXRoleAttribute](https://developer.apple.com/documentation/applicationservices/kaxroleattribute) |
| Element value | [kAXValueAttribute](https://developer.apple.com/documentation/applicationservices/kaxvalueattribute) |
| Selected range | [kAXSelectedTextRangeAttribute](https://developer.apple.com/documentation/applicationservices/kaxselectedtextrangeattribute) |
| Visible range | [kAXVisibleCharacterRangeAttribute](https://developer.apple.com/documentation/applicationservices/kaxvisiblecharacterrangeattribute) |
| Character count | [kAXNumberOfCharactersAttribute](https://developer.apple.com/documentation/applicationservices/kaxnumberofcharactersattribute) |
| String for range | [kAXStringForRangeParameterizedAttribute](https://developer.apple.com/documentation/applicationservices/kaxstringforrangeparameterizedattribute) |
| Bounds for range | [kAXBoundsForRangeParameterizedAttribute](https://developer.apple.com/documentation/applicationservices/kaxboundsforrangeparameterizedattribute) |
| Line for index | [kAXLineForIndexParameterizedAttribute](https://developer.apple.com/documentation/applicationservices/kaxlineforindexparameterizedattribute) |
| Range for line | [kAXRangeForLineParameterizedAttribute](https://developer.apple.com/documentation/applicationservices/kaxrangeforlineparameterizedattribute) |
| Range for index | [kAXRangeForIndexParameterizedAttribute](https://developer.apple.com/documentation/applicationservices/kaxrangeforindexparameterizedattribute) |
| Range for position | [kAXRangeForPositionParameterizedAttribute](https://developer.apple.com/documentation/applicationservices/kaxrangeforpositionparameterizedattribute) |
| AX value wrappers | [AXValueType](https://developer.apple.com/documentation/applicationservices/axvaluetype), [AXValueCreate](https://developer.apple.com/documentation/applicationservices/1459351-axvaluecreate), [AXValueGetValue](https://developer.apple.com/documentation/applicationservices/1462933-axvaluegetvalue) |
| Error model | [AXError](https://developer.apple.com/documentation/applicationservices/axerror) |

## API Model

### 1. Permission Gate

GridSelect must call `AXIsProcessTrustedWithOptions` before attempting extraction.

For product UX, use `kAXTrustedCheckOptionPrompt` only from an explicit permission setup flow. The app should explain that Accessibility permission allows reading text exposed by other apps' accessibility trees.

Expected permission behavior:

| Case | Result |
|---|---|
| Trusted process | AX calls can query other applications. |
| Untrusted process | Reads generally fail or return incomplete data. |
| CLI probe | The launched process or host terminal may need to be granted Accessibility access. |
| MVP app | The signed GridSelect app must be granted Accessibility access in System Settings. |

Screen Recording permission is not part of this spike because the MVP path does not capture screenshots.

### 2. Candidate Element Discovery

Use both focused-element and rectangle hit-testing paths:

| Path | API | Why it matters |
|---|---|---|
| Focused text element | `AXUIElementCreateSystemWide` + `kAXFocusedUIElementAttribute` | Best fit when the user selects inside the active terminal/editor/log view. |
| Element at rectangle center | `AXUIElementCopyElementAtPosition` on the system-wide object | Helps when focus remains on a container but the rectangle is over a child text element. |
| App root fallback | `AXUIElementCreateApplication(pid)` | Useful for app-scoped traversal or debugging, but too broad for MVP extraction by itself. |

The extractor should inspect candidate attributes with `AXUIElementCopyAttributeNames` and parameterized attributes with `AXUIElementCopyParameterizedAttributeNames`. It should choose the smallest text-bearing element that supports range text and range bounds.

### 3. Text Sources

| Source | Use | MVP status |
|---|---|---|
| `kAXStringForRangeParameterizedAttribute` | Read exact substring for a `CFRange`. | Primary extraction path. |
| `kAXVisibleCharacterRangeAttribute` | Determine the scrolled visible character range. | Primary visible-window limiter when present. |
| `kAXNumberOfCharactersAttribute` | Determine full editable text length. | Useful fallback for full-range probing. |
| `kAXValueAttribute` | Read full element value in some text controls. | Diagnostic/fallback only; not enough for rectangular extraction without geometry. |
| `kAXSelectedTextRangeAttribute` | Understand current selection/caret range. | Diagnostic only; MVP should not mutate selection. |

Apple documents these ranges as character ranges, not byte ranges. Production slicing must therefore handle grapheme clusters carefully. The MVP can start with monospace ASCII-heavy targets but should not corrupt Unicode output.

### 4. Range Geometry

`kAXBoundsForRangeParameterizedAttribute` is the key geometry API. Apple's legacy attribute reference describes it as the bounding rectangle a sighted user would see on the display screen, "in pixels"; in practice AX geometry is reported in global **top-left-origin** screen coordinates matching Core Graphics display space, and on modern systems these behave as point values rather than backing pixels. The points-vs-pixels question must be settled empirically on a Retina display as part of fixture validation.

The MVP should treat coordinate conversion as a first-class implementation concern:

| Concern | Constraint |
|---|---|
| Overlay coordinates | AppKit overlay windows reason in points with a **bottom-left** screen origin; the issue #7 spike returns `SelectionRect` in that space. |
| AX range bounds | Global **top-left-origin** screen coordinates (legacy docs say "pixels"); confirm point/pixel behavior on Retina during validation. |
| Y-axis flip | AppKit (bottom-left) and AX/CG (top-left) origins differ; the flip must happen exactly once, at the boundary defined by the issue #9 coordinate contract. |
| Multi-display layouts | Rectangles must be normalized to the same global coordinate space before intersection. |
| Retina displays | Backing scale must be tested; never assume points equal pixels. |

`AXValueCreate` and `AXValueGetValue` are needed to pass `CFRange` into parameterized attributes and decode returned `CGRect` / `CFRange` values.

## Rectangular Extraction Algorithm

Recommended MVP algorithm:

1. Verify Accessibility trust.
2. Capture the user rectangle in global top-left-origin screen coordinates,
   converted once from the overlay's AppKit bottom-left space per the issue #9
   coordinate contract.
3. Build candidate AX elements from the focused element and the element at the rectangle center.
4. Pick the first candidate that supports:
   - `kAXStringForRangeParameterizedAttribute`
   - `kAXBoundsForRangeParameterizedAttribute`
   - at least one usable range limiter or line/range mapping API
5. Determine the candidate visible range:
   - Prefer `kAXVisibleCharacterRangeAttribute`.
   - Fall back to a bounded full-text range from `kAXNumberOfCharactersAttribute`.
   - Reject unbounded elements that expose only a full value string.
6. Enumerate visible lines:
   - Use `kAXLineForIndexParameterizedAttribute` for visible start/end indexes.
   - Use `kAXRangeForLineParameterizedAttribute` for each line.
   - For each line range, use `kAXBoundsForRangeParameterizedAttribute` and intersect with the selection rectangle.
7. For intersecting monospace lines:
   - Read line text with `kAXStringForRangeParameterizedAttribute`.
   - Estimate character cell width from range bounds and character count.
   - Convert rectangle left/right offsets to column indexes.
   - Slice line text by columns and preserve leading/trailing spaces.
8. If line APIs are missing:
   - Try `kAXRangeForPositionParameterizedAttribute` at rectangle corners.
   - If that fails, optionally scan per-character or small range bounds inside the visible range.
   - If geometry remains unavailable, mark the target unsupported.
9. Return rows joined with `\n`.

The production extractor should enforce timeouts and maximum scanned character counts. Accessibility calls can cross process boundaries and should not block the overlay UI.

## Failure Modes

| Failure | Typical signal | MVP behavior |
|---|---|---|
| Accessibility permission missing | `AXIsProcessTrustedWithOptions` is false; AX calls fail. | Show permission setup; do not attempt OCR. |
| Unsupported attribute | `AXError.attributeUnsupported` or missing attribute name. | Try next candidate element; otherwise unsupported. |
| No value | `AXError.noValue`. | Try fallback source; otherwise unsupported. |
| Messaging failure | `AXError.cannotComplete`. | Retry once with fresh element, then unsupported. |
| Stale element | `AXError.invalidUIElement`. | Re-resolve focused/hit-tested element. |
| Secure text field | Role/value may suppress text. | Always reject; never bypass secure input. |
| Canvas/custom rendering | Text not present in AX tree or lacks range geometry. | Unsupported. |
| Browser virtualization | Only visible or simplified text exposed. | Extract only exposed visible text; document partial support. |
| Wrapped/proportional text | Bounds do not map cleanly to fixed columns. | MVP supports monospace only; reject proportional mode unless later implemented. |
| Unicode graphemes/tabs | Character count does not equal displayed grid cells. | Start with ASCII/monospace fixtures; add grid-width handling later. |
| Coordinate mismatch | AX pixels and overlay points differ. | Normalize by display scale and verify with fixtures. |

## Target Applicability

| Category | Feasibility | Notes |
|---|---|---|
| Terminal / terminal emulator | High for classic monospace views when the visible buffer is exposed as text with range bounds. | Best MVP target. Must verify Terminal.app, iTerm2, Warp, and any GPU/canvas-like terminal separately. |
| Native editor / text area | High for AppKit text views; medium for custom editors. | `AXTextArea`-like elements are likely to expose visible range and bounds. Monaco/Electron editors may need per-app verification. |
| Browser plain-text page | Medium. | Plain text, `<pre>`, and contenteditable regions may expose text. Custom web apps, virtualized rows, and canvas terminals often lack useful range geometry. |
| Log viewer | High for native text/log views; medium for web/Electron virtualized lists; low for canvas-only viewers. | MVP should support visible monospace log panes that expose range text and bounds. |

These ratings are desk-research expectations, not measured results; each cell must be confirmed with the probe (manual fixture procedure below) before implementation depends on it.

This is enough for a useful no-OCR MVP if GridSelect explicitly scopes support to capability-positive monospace targets and reports unsupported apps clearly.

### Manual Fixture Procedure

Use the probe below against at least four visible monospace fixtures after granting Accessibility permission to the probe host:

| Fixture | Setup | Pass condition |
|---|---|---|
| Terminal | Show a command output block with aligned columns. | Focused or hit-tested element exposes range text, range bounds, visible range or character count, and line mapping or per-range geometry. |
| Native editor | Open a plain `.txt` file in a native text editor with a monospace font. | Probe reports a text role, range string support, and bounds for the sampled range. |
| Browser plain text | Open a local/plain text or `<pre>` page in Safari or Chrome. | Probe can identify a text-bearing element and sample the visible text without screenshot access. |
| Log viewer-like pane | Open a native log viewer or a simple monospace log file in a viewer/editor. | Probe can sample visible rows and produce range bounds for the visible text. |

Record each app as `supported`, `partial`, or `unsupported` based on the required capability set, not based on visual appearance.

### Fixture Validation Status

As of 2026-07-08, live fixture runs are blocked in the current environment
because the probe host is not trusted for Accessibility:

```sh
swift spikes/macos-accessibility/ax-text-region-probe.swift --focused-only --max-chars=500
```

Result:

```text
accessibilityTrusted: false
Grant Accessibility permission, then run again.
```

The fixture matrix therefore records the current state as blocked rather than
claiming target support:

| Fixture | Status | Evidence | Required next step |
|---|---|---|---|
| Terminal | Blocked | Accessibility trust is false before app-tree reads. | Grant Accessibility to the terminal or signed GridSelect probe host, then rerun the focused and `--rect=` probes. |
| Native editor | Blocked | Accessibility trust is false before app-tree reads. | Grant Accessibility and capture text role, range text, bounds, visible range, and line mapping results. |
| Browser plain text | Blocked | Accessibility trust is false before app-tree reads. | Grant Accessibility and test Safari/Chrome plain text or `<pre>` content with the rectangle probe. |
| Log viewer-like pane | Blocked | Accessibility trust is false before app-tree reads. | Grant Accessibility and record whether visible monospace rows expose range text and geometry. |

## Probe

This spike includes a lightweight read-only probe:

```sh
swift spikes/macos-accessibility/ax-text-region-probe.swift --rect=100,100,800,400 --max-chars=2000
```

Useful variants:

```sh
swift spikes/macos-accessibility/ax-text-region-probe.swift --focused-only
swift spikes/macos-accessibility/ax-text-region-probe.swift --prompt-permission
```

The probe does not scaffold the app. It only reports Accessibility permission status, focused/hit-tested element roles, supported attributes, supported parameterized attributes, visible ranges, rectangle-derived ranges when `--rect=` can be mapped through `kAXRangeForPositionParameterizedAttribute`, sample text, and sample bounds.

Safety behavior:

- The probe warns that stdout can include arbitrary text exposed by other apps.
- Secure text fields are rejected before selected/visible/string range probing.
- Invalid `--rect=` and `--max-chars=` values are reported on stderr.
- Sample lengths are reported as UTF-16 length to match Accessibility range semantics more closely than Swift `Character` counts.

## Verification

| Check | Result |
|---|---|
| Issue context reviewed | `gh issue view 6 --repo Saber5656/GridSelect` |
| Primary API sources reviewed | Apple Developer Documentation DocC JSON and public doc URLs listed above |
| OCR/screenshots/PDF/image analysis | Kept out of scope |
| Probe syntax | `swift spikes/macos-accessibility/ax-text-region-probe.swift --help` |
| Local permission probe | `swift spikes/macos-accessibility/ax-text-region-probe.swift --focused-only --max-chars=500` returned `accessibilityTrusted: false`; live app tree testing requires granting Accessibility permission |
| Fixture matrix | Terminal, native editor, browser plain text, and log viewer-like panes are recorded as blocked until Accessibility permission is granted |

## Follow-Up Constraints

- Implement extraction behind a capability probe, not a global "read screen text" assumption.
- Start automated tests with pure range-to-grid logic before testing live AX elements.
- Build a manual target matrix for Terminal, iTerm2, a native text editor, VS Code/Cursor, Safari/Chrome plain text, and at least one log viewer.
- Keep selection mutation out of the MVP extraction path.
- Treat unsupported apps as normal product state with actionable user messaging.
- Add privacy copy explaining that Accessibility access can expose text from other apps.
