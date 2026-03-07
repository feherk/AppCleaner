import AppKit
import Foundation
import UniformTypeIdentifiers

struct LeftoverGroup: Identifiable, Hashable {
    let id: String // bundleIdentifier
    let bundleIdentifier: String
    var components: [AppComponent]
    var totalSize: Int64
    var note: String

    var icon: NSImage {
        NSWorkspace.shared.icon(for: UTType.bundle)
    }

    static func == (lhs: LeftoverGroup, rhs: LeftoverGroup) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

actor LeftoverScanner {
    private var ownBundleID = "com.appcleaner.AppCleaner"

    func scanLeftovers(installedBundleIDs: Set<String>) -> [LeftoverGroup] {
        let home = NSHomeDirectory()
        let fm = FileManager.default

        let installedLower = Set(installedBundleIDs.map { $0.lowercased() })
        let orgPrefixes = buildOrgPrefixes(from: installedLower)
        let installedOriginal = installedBundleIDs

        var leftovers: [String: [AppComponent]] = [:]

        let bundleIDDirs: [(String, ComponentType)] = [
            ("\(home)/Library/Containers", .containers),
            ("\(home)/Library/Application Support", .applicationSupport),
            ("\(home)/Library/Caches", .caches),
            ("\(home)/Library/HTTPStorages", .httpStorages),
            ("\(home)/Library/WebKit", .webKit),
            ("\(home)/Library/Saved Application State", .savedState),
        ]

        for (directory, type) in bundleIDDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: directory) else { continue }
            for item in items {
                let cleaned = cleanBundleID(item)
                guard shouldInclude(cleaned, installedLower: installedLower, orgPrefixes: orgPrefixes) else { continue }

                let path = (directory as NSString).appendingPathComponent(item)
                let size = FileSize.sizeAt(path: path)
                guard size > 0 else { continue }
                let groupKey = findGroupKey(for: cleaned, existing: &leftovers)
                let component = AppComponent(path: path, type: type, size: size, isSelected: true)
                leftovers[groupKey, default: []].append(component)
            }
        }

        // Preferences
        let prefsDirs = ["\(home)/Library/Preferences", "/Library/Preferences"]
        for prefsDir in prefsDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: prefsDir) else { continue }
            for item in items where item.hasSuffix(".plist") {
                let raw = String(item.dropLast(6))
                let cleaned = cleanBundleID(raw)
                guard shouldInclude(cleaned, installedLower: installedLower, orgPrefixes: orgPrefixes) else { continue }

                let path = (prefsDir as NSString).appendingPathComponent(item)
                let size = FileSize.fileSize(at: path)
                guard size > 0 else { continue }
                let groupKey = findGroupKey(for: cleaned, existing: &leftovers)
                let component = AppComponent(path: path, type: .preferences, size: size, isSelected: true)
                leftovers[groupKey, default: []].append(component)
            }
        }

        // Group Containers
        let groupDir = "\(home)/Library/Group Containers"
        if let items = try? fm.contentsOfDirectory(atPath: groupDir) {
            for item in items {
                let cleaned = cleanBundleID(extractBundleIDFromGroupContainer(item))
                guard shouldInclude(cleaned, installedLower: installedLower, orgPrefixes: orgPrefixes) else { continue }

                let path = (groupDir as NSString).appendingPathComponent(item)
                let size = FileSize.sizeAt(path: path)
                guard size > 0 else { continue }
                let groupKey = findGroupKey(for: cleaned, existing: &leftovers)
                let component = AppComponent(path: path, type: .groupContainers, size: size, isSelected: true)
                leftovers[groupKey, default: []].append(component)
            }
        }

        // Cookies
        let cookiesDir = "\(home)/Library/Cookies"
        if let items = try? fm.contentsOfDirectory(atPath: cookiesDir) {
            for item in items where item.hasSuffix(".binarycookies") {
                let cleaned = cleanBundleID(String(item.dropLast(14)))
                guard shouldInclude(cleaned, installedLower: installedLower, orgPrefixes: orgPrefixes) else { continue }

                let path = (cookiesDir as NSString).appendingPathComponent(item)
                let size = FileSize.fileSize(at: path)
                guard size > 0 else { continue }
                let groupKey = findGroupKey(for: cleaned, existing: &leftovers)
                let component = AppComponent(path: path, type: .cookies, size: size, isSelected: true)
                leftovers[groupKey, default: []].append(component)
            }
        }

        return leftovers.map { bundleID, components in
            let totalSize = components.reduce(0) { $0 + $1.size }
            let note = generateNote(for: bundleID, installedIDs: installedOriginal)
            return LeftoverGroup(
                id: bundleID,
                bundleIdentifier: bundleID,
                components: components,
                totalSize: totalSize,
                note: note
            )
        }
        .filter { $0.totalSize > 0 }
        .sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - Core filtering

    /// Strip known prefixes: "group.", "systemgroup.", team IDs, "TEST_DEVELOPER_ID." etc.
    private func cleanBundleID(_ name: String) -> String {
        var id = name

        // Strip known prefixes
        let prefixesToStrip = ["group.", "systemgroup.", "TEST_DEVELOPER_ID."]
        for prefix in prefixesToStrip {
            if id.hasPrefix(prefix) {
                id = String(id.dropFirst(prefix.count))
            }
        }

        // Strip team ID prefix (e.g. "4C6364ACXT.com.parallels..." or "6HB5Y2QTA3.com.psdr...")
        let parts = id.split(separator: ".", maxSplits: 1)
        if parts.count == 2 {
            let firstPart = String(parts[0])
            if firstPart.count >= 8 && firstPart.count <= 12 && firstPart.allSatisfy({ $0.isLetter || $0.isNumber }) {
                let rest = String(parts[1])
                // Only strip if the rest looks like a bundle ID
                if rest.split(separator: ".").count >= 2 {
                    id = rest
                }
            }
        }

        return id
    }

    /// Combined check: looks like bundle ID + not installed + not system
    private func shouldInclude(_ name: String, installedLower: Set<String>, orgPrefixes: Set<String>) -> Bool {
        guard looksLikeBundleID(name) else { return false }
        if isInstalled(name, installedLower: installedLower, orgPrefixes: orgPrefixes) { return false }
        if name.lowercased() == ownBundleID.lowercased() { return false }
        return true
    }

    private func buildOrgPrefixes(from installedLower: Set<String>) -> Set<String> {
        var prefixes = Set<String>()
        for id in installedLower {
            let parts = id.split(separator: ".")
            if parts.count >= 2 {
                prefixes.insert(parts.prefix(2).joined(separator: "."))
            }
        }
        return prefixes
    }

    private func findGroupKey(for item: String, existing: inout [String: [AppComponent]]) -> String {
        let itemLower = item.lowercased()
        for key in existing.keys {
            let keyLower = key.lowercased()
            if itemLower.hasPrefix(keyLower + ".") || itemLower == keyLower {
                return key
            }
            if keyLower.hasPrefix(itemLower + ".") {
                let entries = existing.removeValue(forKey: key)!
                existing[item] = entries
                return item
            }
        }
        return item
    }

    private func extractBundleIDFromGroupContainer(_ name: String) -> String {
        if name.hasPrefix("group.") {
            return String(name.dropFirst(6))
        }
        let parts = name.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return name }
        let firstPart = String(parts[0])
        if firstPart.count >= 8 && firstPart.count <= 12 && firstPart.allSatisfy({ $0.isLetter || $0.isNumber }) {
            let rest = String(parts[1])
            if rest.hasPrefix("group.") { return String(rest.dropFirst(6)) }
            if rest.hasPrefix("groups.") { return String(rest.dropFirst(7)) }
            return rest
        }
        return name
    }

    private func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        guard parts.count >= 3 else { return false }
        let lower = name.lowercased()
        if lower.hasPrefix("com.apple.") { return false }
        if lower.hasPrefix("is.workflow.") { return false } // macOS Shortcuts
        if lower.hasPrefix("office.") { return false } // Microsoft Office widgets
        if parts[0].count > 20 { return false }
        return true
    }

    /// Helper/service keywords — items with these in their name are likely
    /// shared components of installed apps, not standalone app leftovers
    private let helperKeywords: Set<String> = [
        "updater", "update", "autoupdate", "helper", "sync", "synchronizer",
        "daemon", "crashreporter", "crash", "ipc", "broker", "shim",
        "launcher", "xpc", "shared", "auth", "service", "transport",
        "sdk", "install", "installer", "monitor", "tool", "droplet",
        "serviceprovider", "logtransport", "growthsdk", "ngl", "armdc",
        "genuineservice", "desktopservice", "patchinstall",
    ]

    private func isInstalled(_ name: String, installedLower: Set<String>, orgPrefixes: Set<String>) -> Bool {
        let nameLower = name.lowercased()

        // Exact match
        if installedLower.contains(nameLower) { return true }

        // Sub-bundle of an installed app
        for installed in installedLower {
            if nameLower.hasPrefix(installed + ".") { return true }
        }

        // Organization prefix match — only filter if the item looks like a
        // helper/service component, NOT a standalone app
        let parts = nameLower.split(separator: ".")
        if parts.count >= 2 {
            let orgPrefix = parts.prefix(2).joined(separator: ".")
            if orgPrefixes.contains(orgPrefix) {
                // Check if any part of the name contains a helper keyword
                let nameParts = nameLower.replacingOccurrences(of: ".", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .split(separator: " ")
                    .map(String.init)
                for part in nameParts {
                    if helperKeywords.contains(part) { return true }
                }
                // Also check combined (e.g. "OneDriveStandaloneUpdater" contains "updater")
                for keyword in helperKeywords {
                    if nameLower.contains(keyword) { return true }
                }
            }
        }

        return false
    }

    // MARK: - Note generation

    private func generateNote(for bundleID: String, installedIDs: Set<String>) -> String {
        let lower = bundleID.lowercased()

        let knownApps: [(String, String)] = [
            ("com.kingsgroup.ss", "State of Survival game"),
            ("unity.funplus.misty continent", "Misty Continent game"),
            ("com.coderunnerapp.coderunner", "CodeRunner editor"),
            ("ai.perplexity.app", "Old Perplexity (new: ai.perplexity.mac)"),
            ("com.lastpass", "LastPass password manager"),
            ("com.kagi.kagimacOS", "Kagi browser"),
            ("com.skype.skype", "Skype"),
            ("com.brave.browser", "Brave browser"),
            ("net.tunnelblick.tunnelblick", "Tunnelblick VPN"),
            ("com.2x.client.mac", "2X Remote Desktop"),
            ("com.operasoftware", "Opera browser"),
            ("com.adobe.dunamis", "Adobe analytics/telemetry"),
            ("com.playagames.shakesfidget", "Shakes & Fidget game"),
            ("unity.revival.overload", "Overload game"),
            ("unity.wales interactive.late shift", "Late Shift game"),
            ("com.imangi.templerunplus", "Temple Run game"),
            ("jp.konami.castlevania.ac", "Castlevania game"),
            ("com.pikpok.hip.macosstore", "PikPok game"),
            ("com.ironhidegames.frontiers", "Kingdom Rush Frontiers game"),
            ("com.ivancerra.abusimbelmac", "Abu Simbel game"),
            ("com.funplus.fpc", "FunPlus game"),
            ("com.oracle.java", "Oracle Java"),
            ("pl.kodera.games.deltav", "DeltaV game"),
            ("se.oblador.hush", "Hush Safari extension"),
            ("com.sidetree.translate", "Translate extension"),
            ("dovi.thinkyeah.unarchive.zipmaster", "ZipMaster archiver"),
            ("com.dropbox", "Dropbox"),
            ("com.getdropbox", "Dropbox"),
            ("com.todesktop", "ToDesktop wrapper app"),
            ("net.handmadegame.rooms", "Rooms game"),
            ("com.samuellaska.adbuster", "AdBuster Safari extension"),
            ("shockerella.keys", "Keys Safari extension"),
            ("com.norton", "Norton security"),
            ("org.swift.swiftpm", "Swift Package Manager cache"),
            ("com.gekkotech.macggradio", "GG Radio"),
            ("com.example.markdownviewer", "Test MarkdownViewer app"),
            ("com.facebook.archon", "Facebook Messenger"),
            ("com.facebook.family", "Facebook"),
            ("lmi.lastpass", "LastPass"),
            ("org.cups", "CUPS printing system"),
            ("com.amanitadesign.machinarium", "Machinarium game"),
            ("com.segment.storage", "Analytics SDK leftover"),
            ("com.amplitude.storage", "Analytics SDK leftover"),
            ("org.python.python", "Python interpreter"),
            ("org.viceteam", "VICE emulator"),
            ("no.fengestad.fs-uae", "FS-UAE emulator"),
            ("org.gamesnostalgia", "Games Nostalgia"),
            ("com.duanruiying.pdfmergeplus", "PDF Merge Plus"),
            ("org.sparkle-project", "Sparkle updater framework"),
            ("org.andymatuschak.sparkle", "Sparkle updater framework"),
            ("com.unity3d", "Unity game engine"),
            ("unity.milkstone", "Ziggurat game"),
            ("com.rockysandstudio", "RSS reader"),
        ]

        for (prefix, description) in knownApps {
            if lower.hasPrefix(prefix) {
                return description
            }
        }

        return "Not installed"
    }
}
