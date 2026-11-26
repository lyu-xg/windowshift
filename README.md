# WindowShift

WindowShift combines modifier-held mouse movement and resizing with keyboard layouts and screen-edge snapping in one lightweight macOS menu-bar app. It runs on macOS 13 (Ventura) or later, has zero external dependencies, and builds with the Xcode Command Line Tools.

## Install

### Homebrew (signed & notarized universal build)

```sh
brew install --cask lyu-xg/tap/windowshift
```

Or download `WindowShift-v*-universal.zip` directly from [GitHub Releases](https://github.com/lyu-xg/windowshift/releases) and drag `WindowShift.app` into `/Applications`.

## Build and test

```sh
# Native build
./build.sh
open build/WindowShift.app

# Universal build (Apple Silicon + Intel)
./build.sh --universal

# Optional Developer ID signing (preserves Accessibility permission across updates)
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh --universal

# Run unit tests
swift test
```

If you want to keep the app, copy `build/WindowShift.app` into `/Applications` before approving it under **System Settings → Privacy & Security → Accessibility**. When Accessibility or Input Monitoring is missing, the menu-bar icon dims and displays a badge.

A Homebrew Cask definition is also included in `Casks/windowshift.rb`, and pushing a `v*` tag builds and publishes a universal GitHub Release via `.github/workflows/release.yml` (with optional Developer ID signing and notarization when `APPLE_SIGNING_*` / `APPLE_NOTARY_*` secrets are configured).

## Defaults

| Action | Default |
| --- | --- |
| Move the window under the pointer | Hold **Control–Command** and move the mouse |
| Resize the window under the pointer | Hold **Control–Shift–Command** and move the mouse |
| Left, right, top, or bottom half | **Control–Option** + arrow |
| Upper-left, upper-right, lower-left, or lower-right quarter | **Control–Option** + U, I, J, or K |
| Left, middle, or right third | **Control–Option** + 1, 2, or 3 |
| Maximize, center, or restore | **Control–Option** + Return, C, or Delete |
| Move to previous or next display | **Control–Option** + [ or ] |

Repeat an edge shortcut to cycle from half to one-third to two-thirds. For edge snapping, move a window toward a screen edge or corner and release when the preview appears (works with the move chord or a title-bar drag; bottom-edge zones snap to thirds). Shortcut keys adapt to the active ASCII-capable keyboard layout (QWERTY, AZERTY, QWERTZ, Dvorak, Colemak).

## Configuration

Use **Settings…** (`⌘,`) from the menu bar to adjust chords, window gap, toggles, and record keyboard shortcuts, or edit `~/.config/windowshift/config.json` (or `$XDG_CONFIG_HOME/windowshift/config.json`) directly. WindowShift watches the resolved file and parent directory so symlinked dotfiles and atomic editor saves hot-reload settings and re-register hotkeys automatically. When `config.json` is absent, WindowShift falls back to `UserDefaults`.

```json
{
  "moveChord": "opt+cmd",
  "resizeChord": "shift+cmd",
  "gapSize": 0,
  "edgeSnapping": true,
  "smartResize": false,
  "focusWindow": false,
  "snapToNearbyWindows": true,
  "ignoredApps": [
    "com.parallels.desktop.console"
  ],
  "ignoredGestureApps": [
    "com.pointum.hazeover"
  ],
  "ignoredShortcutApps": [
    "com.microsoft.rdc.macos"
  ],
  "shortcuts": {
    "leftHalf": "opt+cmd+h",
    "rightHalf": "opt+cmd+l",
    "maximize": "opt+cmd+return",
    "centerThird": null
  }
}
```

- `gapSize`: outer screen margin and spacing between adjacent panes (`0–100` px).
- `ignoredApps`: bundle IDs excluded from both mouse gestures and global shortcuts (hotkeys are temporarily unregistered while an excluded app is frontmost).
- `ignoredGestureApps` / `ignoredShortcutApps`: fine-grained exclusions for gestures or shortcuts only.
- `shortcuts`: set any layout to `null` (or omit it) to leave it unbound.

### Migrating from Rectangle and Swift Shift

Quit Rectangle, Swift Shift, and WindowShift, then run `open /Applications/WindowShift.app --args --import-settings`. WindowShift imports supported gestures, layout bindings, gap size, exclusions, focus, and snapping settings and writes `~/.config/windowshift/config.json` if one does not already exist.

## Notes

- WindowShift operates on standard windows (`AXStandardWindow`) with writable Accessibility geometry, temporarily suspends `AXEnhancedUserInterface` for Chromium/Electron apps during resize/move, and clamps oversized minimum-size windows inside the visible display frame.
- Ad-hoc signatures (`codesign --sign -`) change on rebuild. If a local ad-hoc update stops responding, remove the old Accessibility entry and add `/Applications/WindowShift.app` again.
- Inspired by [Swift Shift](https://github.com/pablopunk/SwiftShift) and [Rectangle](https://github.com/rxhanson/Rectangle). Independent MIT-licensed Swift implementation based on public macOS APIs.
