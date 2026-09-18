# NexaBar

**Your Mac. One glance away.**

NexaBar is a native macOS menu-bar utility prototype that combines:

- CPU usage
- Memory usage
- Storage usage
- CPU temperature (best-effort AppleSMC reading)
- Download/upload bandwidth
- Master volume control + mute
- Local clipboard text history
- Region screenshot → clipboard
- Compact / Balanced / Full menu-bar layouts

This is an **MVP / development build**, not yet a production-ready paid release. The proposed commercial model is **$9.99 one-time for Pro, no subscription**. Payment/license activation is intentionally not wired yet because that requires your own payment provider account, signing identity, bundle ID, privacy policy, and production credentials.

---

## Which editor should I use: Xcode or VS Code?

### Recommended: Xcode

Use **Xcode** for NexaBar because it is a native macOS Swift app. Xcode is best for:

- Swift/macOS debugging
- Console logs and crash inspection
- Code signing
- Developer ID distribution
- Notarization
- Profiling CPU/memory usage

This project is a Swift Package, so you can open `Package.swift` directly in Xcode. No generated `.xcodeproj` is required.

### VS Code also works for editing

You can edit the same files in VS Code and run the app from Terminal with `swift run NexaBar`, but you still need Apple's Xcode / Command Line Tools installed to compile native macOS code.

---

# 1. Requirements

Recommended development machine:

- macOS 13 Ventura or later
- Apple Silicon or Intel Mac
- Xcode 15+ (newer Xcode is fine)

Install Xcode from the Mac App Store, then open it once and accept the license/components.

Verify tools in Terminal:

```bash
xcode-select -p
swift --version
xcrun --version
```

If command-line tools are missing:

```bash
xcode-select --install
```

---

# 2. Open and run in Xcode — easiest route

1. Extract the NexaBar project folder.
2. Open Terminal.
3. Go into the project:

```bash
cd /path/to/NexaBar
```

4. Open the Swift package in Xcode:

```bash
open Package.swift
```

5. In Xcode's top toolbar, select:

```text
Scheme: NexaBar
Destination: My Mac
```

6. Press the **Run ▶** button, or press:

```text
⌘R
```

7. NexaBar will not appear in the Dock. Look at the macOS menu bar at the top-right.
8. Click the NexaBar gauge icon to open the control panel.

If CPU starts at 0%, wait for the second refresh. CPU usage is calculated from the delta between two samples.

---

# 3. Run from Terminal / VS Code

From the project folder:

```bash
swift run NexaBar
```

Stop it with:

```text
Control + C
```

You can open the folder in VS Code with:

```bash
code .
```

if the `code` command is installed.

---

# 4. What each feature does

## CPU / memory / storage

Read locally using macOS Mach/BSD APIs and filesystem statistics.

## CPU temperature

NexaBar tries AppleSMC temperature sensors and averages the active CPU-related keys it can read.

Important:

- Apple does not provide a simple public "CPU temperature" API for every Mac model.
- SMC sensor keys differ between chips/models.
- If your model does not expose a recognized sensor, NexaBar shows **Unavailable** rather than inventing a value.
- Test this carefully on M1/M2/M3/M4/M5 and Intel Macs before selling.

## Network

Download/upload speed is calculated from active `en*` interfaces such as Wi‑Fi/Ethernet.

## Volume

Master output volume/mute is controlled through macOS AppleScript system volume commands.

## Clipboard

NexaBar stores up to 50 text clipboard entries locally in `UserDefaults`.

No clipboard content is uploaded anywhere.

## Screenshot

`Capture Selection` invokes the built-in macOS `screencapture` tool in interactive mode and places the selected screenshot on the clipboard.

The first time you use screenshot capture, macOS may request Screen Recording permission depending on OS/security settings.

---

# 5. Build a normal `.app`

From the project folder:

```bash
chmod +x Scripts/*.sh
./Scripts/build-app.sh
```

Output:

```text
dist/NexaBar.app
```

Run it:

```bash
open dist/NexaBar.app
```

For local development the build script applies an ad-hoc signature.

---

# 6. Create the `.dmg`

Run:

```bash
./Scripts/make-dmg.sh
```

Output:

```text
dist/NexaBar-0.1.0.dmg
```

Open it:

```bash
open dist/NexaBar-0.1.0.dmg
```

The DMG contains:

```text
NexaBar.app
Applications -> /Applications
```

Users drag NexaBar into Applications.

---

# 7. Change the app version

Example:

```bash
VERSION=0.2.0 BUILD_NUMBER=2 ./Scripts/make-dmg.sh
```

Output:

```text
dist/NexaBar-0.2.0.dmg
```

---

# 8. Important: local DMG vs public DMG

The basic DMG is suitable for **your own testing**.

If you send an ad-hoc/unsigned app to customers, macOS Gatekeeper can show an unidentified-developer warning. For a commercial release, sign and notarize it with an Apple Developer ID.

## Sign with Developer ID

After enrolling in Apple's developer program and obtaining a Developer ID Application certificate, find the signing name:

```bash
security find-identity -v -p codesigning
```

Then:

```bash
export SIGNING_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)"
VERSION=1.0.0 BUILD_NUMBER=100 ./Scripts/make-dmg.sh
```

The `.app` inside the DMG will be signed with Hardened Runtime.

Verify:

```bash
codesign --verify --deep --strict --verbose=2 dist/NexaBar.app
spctl --assess --type execute --verbose=4 dist/NexaBar.app
```

---

# 9. Notarize the public DMG

Store notarization credentials once:

```bash
xcrun notarytool store-credentials "NexaBarNotary" \
  --apple-id "YOUR_APPLE_ID_EMAIL" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

Then submit and staple:

```bash
NOTARY_PROFILE=NexaBarNotary VERSION=1.0.0 ./Scripts/notarize-dmg.sh
```

Finally verify:

```bash
spctl --assess --type open --context context:primary-signature -v dist/NexaBar-1.0.0.dmg
```

---

# 10. Recommended development workflow

Use small commits:

```text
feat: add native menu bar shell
feat: add cpu and memory monitoring
feat: add disk usage gauge
feat: add SMC temperature reader
feat: add network bandwidth monitor
feat: add master volume control
feat: add local clipboard history
feat: add screenshot-to-clipboard workflow
feat: add menu bar display modes
refactor: split monitors into services
fix: handle missing SMC temperature sensors
perf: reduce monitoring refresh overhead
build: add app bundle script
build: add dmg packaging script
release: prepare 0.1.0 beta
```

Push after each stable feature rather than making one huge commit.

---

# 11. Before charging $9.99

Do not sell this exact prototype immediately. Finish these items first:

1. Test on multiple M-series chips and at least one Intel Mac if you intend to support Intel.
2. Profile idle CPU and RAM in Instruments.
3. Add launch-at-login.
4. Add a first-run permission/privacy explanation.
5. Add crash reporting only if it is opt-in/privacy-respecting.
6. Decide whether to distribute only from your website or also through the Mac App Store.
7. Build the actual one-time Pro licensing flow.
8. Add a proper app icon and polished DMG window/background.
9. Add automatic update support for website distribution (Sparkle is a common option).
10. Create privacy policy, EULA/license terms, support email, and refund policy.
11. Test sleep/wake, external displays, Bluetooth audio, and changing network interfaces.
12. Make sure temperature reporting is accurate on each supported Mac family.

---

# 12. Suggested $9.99 Pro model

Proposed commercial positioning:

```text
NexaBar Pro
$9.99 once
No monthly fee
No subscription
```

Possible split later:

### Free

- CPU
- Memory
- Disk
- Basic network speed
- Master volume

### Pro — $9.99 one-time

- Temperature
- Clipboard history
- Screenshot tools
- Advanced menu-bar layouts
- Network history
- Advanced shortcuts
- Per-app audio when implemented

For the beta, keep all features unlocked until the licensing/payment integration is ready.

---

# Current MVP limitations

- Per-app volume mixing is **not implemented yet**; this build controls master volume.
- Clipboard history currently stores **text**, not persistent image history.
- Screenshot capture copies images to the system clipboard but image items are not saved into clipboard history yet.
- CPU temperature is best-effort and hardware-dependent.
- Network metering currently focuses on `en*` interfaces; VPN/tunnel-specific accounting can be added later.
- No payment/license backend is included yet.
- No automatic updater is included yet.
- No custom app icon is included in this first source build.

Those are intentional MVP boundaries rather than hidden failures.

## Per-app audio notes (0.2.x)

NexaBar now uses Apple's public Core Audio Process Tap API for real per-application gain control on macOS 14.2+.
It no longer tries to fake browser/Electron volume through Accessibility or AppleScript. The first time you move an
app slider below 100%, macOS may request **Screen & System Audio Recording** permission. Audio is processed only in
memory and is not recorded or uploaded.

The menu-bar status item also uses a fixed width for each layout so live CPU/network values no longer push other
menu-bar icons left and right.
