# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language

The user communicates in Hungarian. Respond in Hungarian.

## Build & Run

This project builds with `swiftc` directly (not xcodebuild — the user's machine has a simulator plugin issue with xcodebuild).

```bash
bash scripts/build.sh
open dist/AppCleaner.app
```

The build script compiles all Swift sources, creates a .app bundle with Info.plist and entitlements, code signs with `Developer ID Application: Károly Fehér (YG66KQ8KDT)`, and outputs to `dist/AppCleaner.app`.

**When adding new Swift files**, you must add them to the `SOURCES` array in `scripts/build.sh`.

There are no tests or linting configured.

## Architecture

macOS SwiftUI app (non-sandboxed) for uninstalling applications and cleaning up leftover files. Three modes controlled by `ViewMode` enum:

- **Applications** — Lists installed apps, finds their related files (caches, preferences, logs, containers, etc.), allows moving them to Trash
- **Leftovers** — Finds orphaned files from previously uninstalled apps by scanning Library directories for bundle IDs that don't match any installed app
- **Clean Drive** — System-wide cleanup categories (logs, caches, trash, browser data, Xcode junk, etc.)

### Key patterns

- **Services are `actor`-based** (`AppScanner`, `ComponentFinder`, `LeftoverScanner`, `DriveCleanerScanner`) for thread-safe background scanning
- **ViewModel** (`AppCleanerViewModel` in `ContentView.swift`) is `@MainActor` and owns all state
- App scanning recurses up to 3 levels in `/Applications` but never enters `.app` bundles
- Deletion uses `NSWorkspace.shared.recycle()` (moves to Trash, not permanent delete)
- `FileSize.directorySize()` enumerates recursively including hidden files

### Leftover detection logic (LeftoverScanner)

The most complex part. Key steps:
1. `cleanBundleID()` strips prefixes (`group.`, `systemgroup.`, team IDs)
2. `looksLikeBundleID()` requires 3+ dot-separated parts, excludes `com.apple.*`
3. `isInstalled()` checks exact match, sub-bundle prefix, and org-prefix match (only for helper keywords like `updater`, `daemon`, `service`, etc.)
4. `findGroupKey()` groups related bundle IDs under the shortest common prefix
5. `generateNote()` provides human-readable descriptions for known bundle IDs

### Layout

- Apps/Leftovers modes use `NavigationSplitView` (sidebar + detail)
- Clean Drive mode uses a standalone `CleanDriveView` (no split)
- Mode picker is a segmented control in the window toolbar

## Known issues

- **Trash access requires Full Disk Access** — macOS TCC blocks `.Trash` enumeration from code-signed apps without FDA permission. The old reference app has this permission granted.
- The Xcode project file (`AppCleaner.xcodeproj`) may be outdated and missing newer source files; the canonical build method is `scripts/build.sh`.
