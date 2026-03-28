# Swooshy

Swooshy is an experimental open-source macOS window utility aimed at becoming
an open alternative to touchpad-first window tools. The first version focuses
on the reliable part of the stack: a menubar app that uses Accessibility APIs
to move and resize the focused window.

## Current MVP

- Menubar-only app with no Dock presence
- Accessibility permission prompt and refresh flow
- Built-in English and Simplified Chinese localization
- Global hotkeys for all core window actions
- Settings window for language override, hotkey enable/disable, per-action shortcut recording, and per-gesture Dock action mapping
- Experimental Dock gestures backed by private multitouch input
- Focused-window actions:
  - snap left half
  - snap right half
  - maximize to visible frame
  - center a large window
  - minimize the focused window to the Dock
  - close the focused window
  - quit the frontmost application
  - cycle through windows from the same application
- Pure geometry tests for layout behavior

## Why This Scope

The project is intentionally starting with the window engine before raw
trackpad gesture capture. Public macOS gesture APIs are app-local and system
gestures take precedence, so the riskiest input work is deferred until the
core behavior is stable and useful.

## Running the App

1. Open `Package.swift` in Xcode and run the `Swooshy` executable target.
2. Or run `swift run` from the project root.
3. Grant Accessibility access when prompted.
4. Use the menu bar icon to trigger window actions.
5. Open `Settings…` from the menu bar menu to change language and customize shortcuts.
6. Experimental Dock gestures can be toggled in `Settings…`.

## Local Packaging

- Build a local `.app` bundle and zip archive with:
  - `./scripts/package-macos-app.sh`
- Detailed instructions: `docs/local-packaging.md`

## Experimental Dock Gestures

- Hover an application icon in the Dock
- Swipe left with two fingers on the trackpad to cycle that app's windows forward
- Swipe right with two fingers on the trackpad to cycle that app's windows backward
- Swipe down with two fingers on the trackpad to minimize one visible window for that app
- Swipe up with two fingers on the trackpad to restore one minimized window for that app
- Pinch in with two fingers on the trackpad to quit that app (default mapping)
- Every Dock gesture action can be customized in `Settings…`
- This path depends on private multitouch APIs and should be treated as experimental

## Debug Logging

- Debug builds can enable detailed logs from `Settings… > Enable debug logging`
- You can also force logs on at launch with `SWOOSHY_DEBUG_LOGS=1 swift run`
- When enabled, logs are also persisted to `~/Library/Logs/Swooshy/debug.log`
- Release builds keep these verbose logs compiled out for a lighter runtime path

## Default Hotkeys

- `Control + Option + Command + Left Arrow`: snap left half
- `Control + Option + Command + Right Arrow`: snap right half
- `Control + Option + Command + Up Arrow`: maximize to visible frame
- `Control + Option + Command + C`: center large window
- `Control + Option + Command + M`: minimize to Dock
- `Control + Option + Command + W`: close the focused window
- `Control + Option + Command + Q`: quit the frontmost application
- `Control + Option + Command + \``: cycle same-app windows

## Project Structure

- `Sources/Swooshy/SwooshyApp.swift`: App entry point
- `Sources/Swooshy/AppDelegate.swift`: lifecycle bootstrap
- `Sources/Swooshy/StatusBarController.swift`: menu bar UI and action wiring
- `Sources/Swooshy/SettingsStore.swift`: persisted app settings
- `Sources/Swooshy/SettingsWindowController.swift`: SwiftUI-backed settings window
- `Sources/Swooshy/Localization.swift`: localized string lookup
- `Sources/Swooshy/Resources/*.lproj`: language resources
- `Sources/Swooshy/WindowManager.swift`: Accessibility-based focused-window IO
- `Sources/Swooshy/WindowLayoutEngine.swift`: pure layout calculations
- `ATTRIBUTION.md`: tracked reference projects and license discipline

## Roadmap

- Expand settings with layout ratios and launch-at-login behavior
- Add a separate experimental module for raw trackpad input
- Explore private-framework experiments only after the public MVP is solid

## License

This project is licensed under the GNU General Public License v3.0.
See `LICENSE` for the full text and `ATTRIBUTION.md` for reference-project
tracking.
