# NexaBar — minimal UI refresh

A native SwiftUI redesign for macOS 14.2 or newer. The app's existing monitoring,
audio engine, clipboard storage, screenshot capture, shortcuts and update service
are included.

## What changed

- A calm lavender, mint and amber palette with subtle cards, lighter gauge rings,
  smaller labels and consistent spacing.
- Four tabs: Overview, Sound, Clipboard and Settings. The header, navigation and
  shortcut footer stay visible while content scrolls.
- Overview shows live CPU, memory, storage, temperature and network activity,
  with quick actions for screenshot capture and clipboard history.
- Sound gives device names a full row, separates output selection from volume,
  and keeps app volume and mute controls together.
- Clipboard has All / Text / Images filters, search, one-click copy and delete,
  clear-history confirmation and the same design in the Cmd+Shift+V panel.
  Return copies the top search result in either clipboard view.
- Appearance follows macOS by default; System / Light / Dark can be selected.
- New installations default to Compact menu bar mode (CPU + memory). Existing
  preferences are preserved. Balanced mode remains available in Settings.
- Gauges honor Reduce Motion; the background honors Reduce Transparency.
- Update banners and settings observe the update manager directly.

## Run on your Mac

1. Extract this ZIP and open Terminal in the `nexabar` folder (the folder that
   contains `Package.swift`).
2. Quit the existing NexaBar process in Activity Monitor before testing.
3. Run:

```bash
swift build -c release
bash Scripts/build-app.sh
open dist/NexaBar.app
```

The command-line developer tools are required. If they are not installed, run
`xcode-select --install` once and finish the macOS installer.

To make a universal installer for Apple Silicon and Intel Macs:

```bash
bash Scripts/build_dmg.sh
```

It produces `NexaBar.dmg` at the project root. Drag NexaBar into Applications.
The build remains ad-hoc signed unless you supply your own Developer ID through
`SIGNING_IDENTITY`. No release, tag, upload or publication has been performed.

If you prefer to apply the redesign to your existing repository, replace its
`Sources/NexaBar/Views/` folder, `AppDelegate.swift`, `Models/AppState.swift`,
`Scripts/build-app.sh` and `Scripts/build_dmg.sh`. The restored `Package.swift`
is provided because this smaller upload omitted the manifest; preserve any
extra dependencies or build settings in your own original manifest.

## Design preview

Open `Design/preview.html` in a browser to review light and dark layouts, tabs,
clipboard filters and slider styling. It uses sample data and is a visual
reference, not the native application or a connection to your Mac's services.

## Validation

All 19 Swift files were parsed with the Swift tree-sitter grammar, and the shell
scripts were syntax-checked. The archive's plist and resource paths were checked.
Native Swift compilation, macOS layout, Core Audio behavior and hotkeys could not
be executed in the Linux environment used to prepare this update. Build and test
on your Mac before distributing the installer.

On macOS, verify each tab, light/dark/system appearance, clipboard search and
filters, Return-to-copy, Cmd+Shift+V and Escape, volume and mute, screenshot
capture, launch-at-login and update checking. Test the installer on another Mac.
