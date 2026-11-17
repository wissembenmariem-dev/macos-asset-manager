# Asset Manager for macOS

A native menu bar utility that monitors CPU, memory pressure and swap on Apple Silicon Macs, and lets you act on the processes responsible.

## Features

- Live CPU usage per core, memory pressure and swap in the menu bar, colour-coded by threshold
- Top processes ranked by CPU then resident memory, with name, path and bundle identifier
- Runaway detection: sustained high CPU or monotonic memory growth over a configurable window
- Per-process actions: terminate, force quit, suspend, resume, throttle to efficiency cores (`taskpolicy -b`) and restore
- Protected process lists that are never throttled or suspended
- Configurable polling interval and optional LaunchAgent for start at login

## Architecture

```
Sources/AssetManager
├── App/          application lifecycle
├── Monitoring/   system metrics (host_statistics, sysctl) and per-process sampling (libproc)
├── Rules/        runaway detection
├── Actions/      signals and QoS changes
├── Config/       thresholds and protected lists, persisted as JSON
└── UI/           NSStatusItem menu and SwiftUI detail window
```

## Requirements

macOS 13 or later, Swift 5.9 toolchain.

## Build

```bash
cd AssetManager
swift build -c release
./scripts/build-app.sh          # builds AssetManager.app
./scripts/install.sh            # installs the binary and the LaunchAgent
./scripts/uninstall.sh
```

## License

Copyright (c) 2026 Wissem Ben Mariem. All rights reserved. See [LICENSE](LICENSE).
