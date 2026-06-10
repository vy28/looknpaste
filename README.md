# QuickCopy

A lightweight macOS menu bar utility that copies whatever is under your mouse
cursor — and pastes it back — with a single tap of a modifier key. No clicking,
no selecting, no dragging.

The trigger is the **Option** key by default (changeable to Control / Command /
Shift from the menu). QuickCopy *observes* the key rather than consuming it, so
it keeps working normally for typing and shortcuts — only a clean tap (pressed
and released with no other key, click, or scroll in between) fires an action.

**Short tap** is context-aware, in priority order:

- **Swept phrase** — if you just moved the mouse across some text, the tap
  captures the exact phrase/sentence you passed over, punctuation and spacing
  intact.
- **Over a text field** — pastes the clipboard right there, no click needed.
- **Over a browser's "+" new-tab button** (with a URL on the clipboard) — opens
  that URL.
- **Over a link** — copies the link's URL.
- **Over an image** — copies the image itself (needs Screen Recording
  permission, see below).
- **Otherwise** — copies the single word/element under the cursor.

**Long press** (hold past ~0.35s) always copies the *textual* content under the
cursor — over a link this gives its visible text rather than its URL.

QuickCopy runs as a menu bar–only app (no Dock icon) and uses only Swift +
AppKit — no third-party dependencies.

## Requirements

- macOS 13 Ventura or later
- Xcode command-line tools (for `swift build`)

## Build & run

```bash
./build_app.sh            # release build → build/QuickCopy.app
open build/QuickCopy.app
```

For a debug build: `./build_app.sh --debug`.

You can also run the raw executable during development:

```bash
swift run
```

Running the assembled `.app` bundle is recommended, because macOS associates
the Accessibility permission with a signed bundle rather than a loose binary.

## Accessibility permission (required)

QuickCopy reads text from other apps and synthesizes keystrokes, both of which
macOS gates behind **Accessibility** permission.

On first launch an onboarding window explains this and offers a button that
deep-links to **System Settings → Privacy & Security → Accessibility**. Enable
**QuickCopy** there. The app re-checks the permission automatically when it
becomes active, so you do **not** need to relaunch after granting it.

If you rebuild the bundle, you may need to toggle the permission off and on
once for macOS to re-trust the new signature.

## Screen Recording permission (for image copy)

Copying an image under the cursor works by capturing that screen region, which
macOS gates behind a separate **Screen Recording** permission. QuickCopy
requests it the first time you try to copy an image; if you previously denied
it, use **Open Screen Recording Settings…** in the menu bar item.

## Menu

The menu bar item provides:

- **Enable QuickCopy** — toggle the trigger and hover tracking on/off.
- **Trigger Key** — submenu to pick Option (default), Control, Command, or
  Shift as the tap key. A checkmark shows the current choice.
- **Open Accessibility Settings…** — jump straight to the permission pane.
- **Open Screen Recording Settings…** — jump straight to the permission pane
  used for image copying.
- **Quit QuickCopy**.

## How it works

| Component | Responsibility |
|-----------|----------------|
| `AppDelegate` | App lifecycle, status item/menu, permission checks, context dispatch |
| `HotkeyManager` | `CGEventTap` modifier-tap recognizer (short tap vs long press) |
| `HotkeySettings` | Persists the chosen trigger modifier, default Option |
| `HoverTracker` | ~12 Hz mouse polling, range-based sweep accumulation, 300ms reset |
| `TextReader` | AX word/link/image/field extraction with full-element fallback |
| `ScreenCapture` | Screen Recording permission + region capture for image copy |
| `HUDWindow` | Non-activating confirmation overlay (text or image thumbnail) |
| `ClipboardManager` | `NSPasteboard` read/write (text + image) + synthesized ⌘V paste |

The trigger is recognized by observing `.flagsChanged` events: when the chosen
modifier goes down alone, a gesture begins; if any other key, mouse-down, scroll,
or modifier occurs before it is released, the gesture is cancelled (so
Option+click, Option+letter for special characters, ⌘⌥-combos, etc. are
untouched). Holding past the long-press threshold fires immediately; a quick
release fires the short tap. Events are never consumed.

Text extraction is point-in-time: on each query QuickCopy gets the
`AXUIElement` at the mouse position via `AXUIElementCopyElementAtPosition`, then
uses the parameterized attributes `kAXRangeForPositionParameterizedAttribute`
and `kAXStringForRangeParameterizedAttribute` to isolate the word at the cursor.
If those aren't supported it falls back to the element's full `kAXValueAttribute`
string; if even that is unavailable it fails silently. No `AXObserver` /
change-notification machinery is used.

A hover sweep tracks the character-index range the cursor passed over within a
single element, then slices that exact span (expanded to whole words at each
end) out of the element's text — preserving the original punctuation and
spacing rather than re-joining sampled words with single spaces.

Paste-on-hover finds the editable element under the cursor (`AXTextField`,
`AXTextArea`, `AXSearchField`, `AXComboBox`, or any element with a settable
string value), sets its `kAXFocusedAttribute`, activates its owning app, and
synthesizes ⌘V — so the clipboard lands in the field the mouse is over without
a click.

Short-tap priority: **swept phrase** → **editable field** (paste) → **new-tab
button** (`AXButton` whose title/description reads "new tab"/"+", opens a
clipboard URL) → **link** (`kAXURLAttribute`, walking up to 6 ancestors) →
**image** (`AXImage`, captured via screen recording) → **single word/element**.

## Known limitations

Word-level capture and the hover trail rely on apps exposing **parameterized
text attributes** through the Accessibility API. Many apps don't, and in those
QuickCopy **degrades to copying the full focused element's text** (and the hover
trail stays empty, so a press copies that whole element instead of a phrase):

- **Google Chrome and Chromium-based browsers** (often need accessibility mode
  to expose any text at all).
- **Electron apps** (VS Code, Slack, Discord, Notion, etc.).
- **Games and custom-drawn / canvas / OpenGL-Metal UIs**, which expose no text
  elements — these typically yield nothing and QuickCopy fails silently.
- **Java / cross-platform toolkit apps** with partial AX support.
- **Secure input fields** (password fields): AX returns nothing by design, so
  QuickCopy fails silently — no crash, no dialog.

Image copy similarly depends on the app exposing an `AXImage` element with a
valid position/size; canvas-drawn images (e.g. in browsers without full AX
support) won't be detected.

Paste-on-hover and the new-tab-button gesture likewise depend on apps exposing
proper Accessibility roles. In Chrome/Electron a text field or new-tab button
may not be detected, in which case the paste/open simply doesn't fire.

Other notes:

- A **clean tap** of the trigger is required: if you click, scroll, or press
  another key while holding it, nothing fires. This is what keeps Option usable
  for normal typing and shortcuts.
- Using **Option** as the trigger means a deliberate lone Option tap anywhere
  will fire QuickCopy. If that conflicts with your habits, switch the trigger
  to Control or Command from the menu.
