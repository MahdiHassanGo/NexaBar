# NexaBar 0.2.0 changes

- Replaced fake AppleScript/Accessibility app-volume controls with real Core Audio Process Taps.
- App list now shows processes that are actually producing audio instead of every running app.
- Browser/Electron helper audio is grouped back to the owning app using the public process tree.
- App gain and mute persist by bundle identifier.
- Added Screen & System Audio Recording usage description.
- Raised minimum macOS version to 14.2 because Apple's Process Tap API starts there.
- Fixed menu-bar shifting: each layout now uses a stable fixed width and monospaced text.
- Reduced popover from 440×680 to 404×610 and tightened gauges/spacing.
- Removed hard-coded local icon paths; the app now loads its bundled icon.
- Build script now copies AppIcon.icns/AppIcon.png into the .app bundle.

## Important test note

For per-app audio, test the packaged app rather than `swift run`:

```bash
chmod +x Scripts/*.sh
./Scripts/build-app.sh
open dist/NexaBar.app
```

Then start audio in Brave/Discord/Spotify, move that app's slider below 100%, and grant NexaBar
**Screen & System Audio Recording** permission if macOS asks.
