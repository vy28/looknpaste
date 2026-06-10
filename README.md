# QuickCopy

A lightweight macOS menu bar utility that copies the text under your mouse
cursor with a global hotkey — and pastes it back on a double-tap. No clicking,
no selecting, no dragging.

- **⌥⌘C (single press)** — copy the word under the cursor immediately.
- **⌥⌘C (double-tap within ~400ms)** — paste the clipboard at the
  keyboard-focused location.
- **Hover trail** — sweep the mouse across text and a single ⌥⌘C captures the
  whole phrase you passed over.

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

## Menu

The menu bar item provides:

- **Enable QuickCopy** — toggle the hotkey and hover tracking on/off.
- **Open Accessibility Settings…** — jump straight to the permission pane.
- **Quit QuickCopy**.

## How it works

| Component | Responsibility |
|-----------|----------------|
| `AppDelegate` | App lifecycle, status item/menu, permission checks |
| `HotkeyManager` | `CGEventTap` hotkey listener + double-tap detection |
| `HoverTracker` | ~12 Hz mouse polling, hover-trail accumulation, 300ms reset |
| `TextReader` | AX word extraction with full-element fallback |
| `HUDWindow` | Non-activating confirmation overlay |
| `ClipboardManager` | `NSPasteboard` read/write + synthesized ⌘V paste |

Text extraction is point-in-time: on each query QuickCopy gets the
`AXUIElement` at the mouse position via `AXUIElementCopyElementAtPosition`, then
uses the parameterized attributes `kAXRangeForPositionParameterizedAttribute`
and `kAXStringForRangeParameterizedAttribute` to isolate the word at the cursor.
If those aren't supported it falls back to the element's full `kAXValueAttribute`
string; if even that is unavailable it fails silently. No `AXObserver` /
change-notification machinery is used.

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

Other notes:

- Paste targets the app with **keyboard focus**, which may differ from the app
  under the mouse. This is intentional: copy from one place, paste into another.
- Spacing in a captured hover trail is normalized to single spaces between the
  swept words.
