# AppCleaner

A lightweight macOS app uninstaller and system cleaner built with SwiftUI.

![AppCleaner Screenshot](https://img.shields.io/badge/platform-macOS_14+-blue) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

### Applications
- Scans `/Applications` and `~/Applications` for installed apps
- Finds all related files: caches, preferences, logs, containers, saved state, cookies, crash reports, and more
- Shows app icon, name, bundle ID, and total size for each application
- Select/deselect individual components before uninstalling
- Moves files to Trash (safe, reversible deletion)

### Leftovers
- Detects orphaned files from previously uninstalled applications
- Scans Library directories for bundle IDs that don't match any installed app
- Smart filtering: distinguishes between standalone app leftovers and helper components of installed apps
- Human-readable descriptions for known applications

### Clean Drive
- System-wide cleanup across 8 categories:
  - **Log files** — system logs, app logs, analytics data
  - **Cache files** — user and system caches, container caches, temp files
  - **Trash** — items in the Trash
  - **Browser data** — browser caches (Chrome, Firefox, Brave, Opera, Safari)
  - **Mail cache** — Apple Mail caches
  - **Xcode junk** — DerivedData, Archives, Device Support, Simulator caches
  - **iOS device backups** — old iPhone/iPad backups
  - **Installers** — DMG, PKG, and ISO files in Downloads
- Visual color bar showing category proportions
- Confirmation dialog before cleanup

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (arm64)
- **Full Disk Access** recommended for complete results (Trash scanning, etc.)

## Installation

1. Download the latest DMG from [Releases](https://github.com/feherk/appcleaner/releases)
2. Open the DMG and drag AppCleaner to Applications
3. On first launch, grant Full Disk Access: **System Settings → Privacy & Security → Full Disk Access → Add AppCleaner**

## Building from Source

```bash
# Build .app bundle
./scripts/build.sh

# Build signed & notarized DMG
./scripts/build-dmg.sh
```

Requires Xcode Command Line Tools and a valid Developer ID certificate for code signing.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Author

Károly Fehér (FK)
