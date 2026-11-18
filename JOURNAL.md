# Journal

## 2026-11-19

- Built a standalone MIT-licensed AppKit app with modifier-only move and resize, keyboard layouts, and edge snapping. A modifier move commits the preview on release.
- Built with the Swift command-line tools. Bundle signature and plist validation passed. Geometry checks covered layout bounds, thirds, edge zones, and resize anchors with negative display coordinates.
- Launch Services accepted the app. The desktop inspection timed out, so interactive gesture verification still requires an Accessibility grant and a live desktop check.

## Settings migration

- Imported the user's two Swift Shift gestures and 18 active Rectangle layout bindings. Verified the saved WindowShift preferences against both original preferences on disk.
- Added nearby-window alignment and migrated focus, app exclusions, and snapping. Added the five extra layout actions needed to retain the configured Rectangle bindings.
- Quit the two original apps and confirmed the rebuilt WindowShift process started with the imported settings.

## Installation and handoff

- Installed the signed bundle in Applications and verified its login item in System Settings. Removed Rectangle and Swift Shift from Open at Login.
- Diagnosed the first launch failure as an Accessibility grant tied to an earlier build signature. The user confirmed the installed build worked after reapproving it.
