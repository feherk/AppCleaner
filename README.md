# AppCleaner

A free, open-source macOS app uninstaller and system cleaner. A lightweight alternative to CleanMyMac, AppZapper, and other paid cleanup utilities — built natively with SwiftUI.

[![Platform](https://img.shields.io/badge/platform-macOS_14+-blue)](https://github.com/feherk/appcleaner/releases)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/feherk/appcleaner)](https://github.com/feherk/appcleaner/releases/latest)

## Features

### Uninstall Applications
- Scans `/Applications` and `~/Applications` for installed apps
- Finds **all related files**: caches, preferences, logs, containers, saved state, cookies, crash reports, and more
- Shows app icon, name, bundle ID, and total size
- Select/deselect individual components before removing
- Moves files to Trash (safe, reversible deletion)

### Clean Up Leftovers
- Detects **orphaned files** from previously uninstalled applications
- Scans Library directories for bundle IDs that don't match any installed app
- Smart filtering: distinguishes between standalone app leftovers and helper components
- Multi-selection support (Cmd+click, Shift+click) for batch cleanup
- Human-readable descriptions for known applications

### Clean Drive
- System-wide cleanup across **8 categories**:
  - **Log files** — system logs, app logs, analytics data
  - **Cache files** — user and system caches, container caches, temp files
  - **Trash** — items in the Trash
  - **Browser data** — Chrome, Firefox, Brave, Opera, Safari caches
  - **Mail cache** — Apple Mail caches
  - **Xcode junk** — DerivedData, Archives, Device Support, Simulator caches
  - **iOS device backups** — old iPhone/iPad backups
  - **Installers** — DMG, PKG, and ISO files in Downloads
- Visual color bar showing category proportions
- Confirmation dialog before cleanup

## Why AppCleaner?

- **Free & open-source** — no subscriptions, no ads, no telemetry
- **Native SwiftUI** — fast, lightweight, feels like a system app
- **Safe** — moves files to Trash instead of permanent deletion
- **No App Store restrictions** — full disk access for thorough cleaning
- **Transparent** — read the source code, know exactly what it does

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (arm64)
- **Full Disk Access** recommended for complete results (System Settings → Privacy & Security → Full Disk Access)

## Installation

1. Download the latest release from [**Releases**](https://github.com/feherk/appcleaner/releases/latest)
2. Unzip and drag **AppCleaner.app** to your Applications folder
3. On first launch, grant Full Disk Access for best results

## Building from Source

```bash
git clone https://github.com/feherk/appcleaner.git
cd appcleaner
./scripts/build.sh
open dist/AppCleaner.app
```

Requires Xcode Command Line Tools and a valid Developer ID certificate for code signing.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Author

Károly Fehér
