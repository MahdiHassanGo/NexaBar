# NexaBar Quick Start

## Use Xcode (recommended)

```bash
cd NexaBar
open Package.swift
```

In Xcode: select **NexaBar → My Mac → Run (⌘R)**.

## Terminal route

```bash
cd NexaBar
swift run NexaBar
```

## Build `.app`

```bash
chmod +x Scripts/*.sh
./Scripts/build-app.sh
open dist/NexaBar.app
```

## Build `.dmg`

```bash
./Scripts/make-dmg.sh
open dist/NexaBar-0.1.0.dmg
```

## Public release

Use a Developer ID certificate + Apple notarization. See `README.md` sections 8–9.
