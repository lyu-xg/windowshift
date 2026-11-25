# WindowShift

WindowShift combines modifier-held mouse movement with keyboard layouts and screen-edge snapping in one macOS menu-bar app. It runs on macOS 13 or later and builds using the Xcode Command Line Tools.

## Build and run

```sh
./build.sh
open build/WindowShift.app
```

If you want to keep the app, move it to Applications before granting permission. From the menu-bar icon, choose **Enable Accessibility…** and enable WindowShift in System Settings. Pause other window managers while testing overlapping gestures or hotkeys. If a drag shows two snap previews, disable the overlapping snap feature in macOS or in the other window manager.

To use existing Swift Shift and Rectangle preferences, quit both apps and WindowShift, then run `open build/WindowShift.app --args --import-settings`. This saves the supported gesture and layout bindings, exclusions, focus, and snapping settings as WindowShift preferences. If Launch at Login was enabled, WindowShift requests its own login item. Rectangle's Todo feature is outside the window layout controls.

| Action | Default |
| --- | --- |
| Move the window under the pointer | Hold **Control–Command** and move the mouse |
| Resize the window under the pointer | Hold **Control–Shift–Command** and move the mouse |
| Left, right, top, or bottom half | **Control–Option** + arrow |
| Upper-left, upper-right, lower-left, or lower-right quarter | **Control–Option** + U, I, J, or K |
| Left, middle, or right third | **Control–Option** + 1, 2, or 3 |
| Maximize, center, or restore | **Control–Option** + Return, C, or Delete |
| Move to previous or next display | **Control–Option** + [ or ] |

Repeat an arrow shortcut to cycle from half to one-third to two-thirds. For edge snapping, move a window toward a screen edge or corner and release when the preview appears. This works with the move chord or a title bar drag. Bottom-edge zones snap to thirds.

The menu lets you choose move and resize modifiers, toggle quadrant resizing and snapping to nearby windows, focus the window during gestures, pause the utility, and launch at login. WindowShift operates on standard windows that expose writable Accessibility geometry. Full-screen windows are skipped, and an app can enforce its own size limits.

Inspired by [Swift Shift](https://github.com/pablopunk/SwiftShift) and [Rectangle](https://github.com/rxhanson/Rectangle). This is an independent Swift implementation based on public macOS APIs.

## Configuration

WindowShift watches `~/.config/windowshift/config.json` (or `$XDG_CONFIG_HOME/windowshift/config.json`) and hot-reloads changes on save, including keyboard shortcuts and symlinked dotfiles. Choose **Open Config…** from the menu bar to generate or open it. When `config.json` is absent, WindowShift falls back to `UserDefaults`.

```json
{
  "moveChord": "opt+cmd",
  "resizeChord": "shift+cmd",
  "edgeSnapping": true,
  "smartResize": false,
  "focusWindow": false,
  "snapToNearbyWindows": true,
  "ignoredGestureApps": [],
  "shortcuts": {
    "leftHalf": "opt+cmd+h",
    "rightHalf": "opt+cmd+l",
    "maximize": "opt+cmd+return",
    "centerThird": null
  }
}
```

## Installing locally

Copy the built bundle into `/Applications` before approving it under **System Settings → Privacy & Security → Accessibility**. Ad-hoc signatures change when the app is rebuilt. If an update stops responding, remove the old Accessibility entry and add the installed copy again. To start it automatically, add the installed bundle under **General → Login Items & Extensions → Open at Login**.
