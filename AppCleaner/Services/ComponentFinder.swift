import Foundation

actor ComponentFinder {
    func findComponents(for app: AppInfo, installedBundleIDs: Set<String>) -> [AppComponent] {
        let bundleID = app.bundleIdentifier
        let appName = app.name
        let home = NSHomeDirectory()
        let fm = FileManager.default
        var components: [AppComponent] = []

        // App bundle itself
        components.append(AppComponent(
            path: app.path,
            type: .appBundle,
            size: app.bundleSize,
            isSelected: true
        ))

        // Vendor prefix (e.g. "com.binarynights") lets us catch shared helper
        // components whose bundle ID doesn't contain the app name/bundle ID,
        // such as privileged helpers and ask-pass tools. Only used when NO other
        // installed app shares the prefix — for multi-app vendors (com.microsoft,
        // com.google, …) it would sweep up sibling apps' containers and helpers.
        var vendorPatterns = [bundleID]
        if let vendorPrefix = Self.vendorPrefix(from: bundleID),
           !Self.vendorShared(vendorPrefix, ownBundleID: bundleID, installed: installedBundleIDs) {
            vendorPatterns.append(vendorPrefix)
        }

        // Search locations: (directory, type, patterns)
        let searchSpecs: [(String, ComponentType, [String])] = [
            ("\(home)/Library/Application Support", .applicationSupport, [bundleID, appName]),
            ("\(home)/Library/Caches", .caches, [bundleID, appName]),
            ("\(home)/Library/Logs", .logs, [appName, bundleID]),
            ("\(home)/Library/Saved Application State", .savedState, ["\(bundleID).savedState"]),
            ("\(home)/Library/Containers", .containers, vendorPatterns),
            ("\(home)/Library/HTTPStorages", .httpStorages, [bundleID]),
            ("\(home)/Library/WebKit", .webKit, [bundleID]),
            ("\(home)/Library/Application Support/CrashReporter", .crashReports, [bundleID, appName]),
            // System-wide startup jobs and privileged helpers (root-owned).
            ("\(home)/Library/LaunchAgents", .launchAgents, vendorPatterns),
            ("/Library/LaunchAgents", .launchAgents, vendorPatterns),
            ("/Library/LaunchDaemons", .launchDaemons, vendorPatterns),
            ("/Library/PrivilegedHelperTools", .privilegedHelpers, vendorPatterns),
        ]

        for (directory, type, patterns) in searchSpecs {
            guard fm.fileExists(atPath: directory) else { continue }
            for match in findMatches(in: directory, patterns: patterns) {
                let size = FileSize.sizeAt(path: match)
                components.append(AppComponent(path: match, type: type, size: size, isSelected: true))
            }
        }

        // Preferences - plist files (boundary match so "com.foo.app" doesn't
        // catch "com.foo.app2.plist", but still catches "com.foo.app.helper.plist")
        let prefsDir = "\(home)/Library/Preferences"
        if let items = try? fm.contentsOfDirectory(atPath: prefsDir) {
            for item in items where item.hasSuffix(".plist")
                && Self.matchesBoundary(String(item.dropLast(6)), bundleID) {
                let path = (prefsDir as NSString).appendingPathComponent(item)
                let size = FileSize.fileSize(at: path)
                components.append(AppComponent(path: path, type: .preferences, size: size, isSelected: true))
            }
        }

        // Group Containers — strip "group."/team-ID prefixes before matching
        let groupDir = "\(home)/Library/Group Containers"
        if let items = try? fm.contentsOfDirectory(atPath: groupDir) {
            for item in items {
                let cleaned = Self.stripContainerPrefixes(item)
                guard vendorPatterns.contains(where: { Self.matchesBoundary(cleaned, $0) }) else { continue }
                let path = (groupDir as NSString).appendingPathComponent(item)
                let size = FileSize.sizeAt(path: path)
                components.append(AppComponent(path: path, type: .groupContainers, size: size, isSelected: true))
            }
        }

        // Cookies
        let cookiesDir = "\(home)/Library/Cookies"
        if let items = try? fm.contentsOfDirectory(atPath: cookiesDir) {
            for item in items where item.hasSuffix(".binarycookies")
                && Self.matchesBoundary(String(item.dropLast(14)), bundleID) {
                let path = (cookiesDir as NSString).appendingPathComponent(item)
                let size = FileSize.fileSize(at: path)
                components.append(AppComponent(path: path, type: .cookies, size: size, isSelected: true))
            }
        }

        // Diagnostic Reports — the /Library ones are root-owned and removing
        // them triggers an admin prompt, so they're listed unselected.
        let diagSpecs: [(String, Bool)] = [
            ("/Library/Logs/DiagnosticReports", false),
            ("\(home)/Library/Logs/DiagnosticReports", true),
        ]
        for (diagDir, selected) in diagSpecs {
            if let items = try? fm.contentsOfDirectory(atPath: diagDir) {
                for item in items where Self.matchesBoundary(item, appName) {
                    let path = (diagDir as NSString).appendingPathComponent(item)
                    let size = FileSize.fileSize(at: path)
                    components.append(AppComponent(path: path, type: .crashReports, size: size, isSelected: selected))
                }
            }
        }

        return components
    }

    /// Derives the vendor prefix (first two reverse-DNS components, e.g.
    /// "com.binarynights") from a bundle ID. Returns nil for Apple bundles or
    /// IDs too short to have a distinct vendor namespace, to avoid over-matching.
    static func vendorPrefix(from bundleID: String) -> String? {
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        let prefix = parts.prefix(2).joined(separator: ".")
        if prefix.lowercased() == "com.apple" { return nil }
        return prefix
    }

    /// True when another installed app (not the app itself or its sub-bundles)
    /// lives under the same vendor prefix.
    static func vendorShared(_ vendorPrefix: String, ownBundleID: String, installed: Set<String>) -> Bool {
        let prefix = vendorPrefix.lowercased() + "."
        let own = ownBundleID.lowercased()
        return installed.contains { id in
            let idLower = id.lowercased()
            return idLower != own
                && !idLower.hasPrefix(own + ".")
                && idLower.hasPrefix(prefix)
        }
    }

    /// Case-insensitive match requiring a word boundary: the item either equals
    /// the pattern or continues with a separator (".", " ", "-", "_"), so
    /// "Fork" matches "Fork" and "Fork Data" but not "ForkLift".
    static func matchesBoundary(_ item: String, _ pattern: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        let itemLower = item.lowercased()
        let patternLower = pattern.lowercased()
        guard itemLower.hasPrefix(patternLower) else { return false }
        if itemLower.count == patternLower.count { return true }
        let boundary = itemLower[itemLower.index(itemLower.startIndex, offsetBy: patternLower.count)]
        return boundary == "." || boundary == " " || boundary == "-" || boundary == "_"
    }

    /// "group.com.foo.app", "TEAMID.com.foo.app", "TEAMID.group.com.foo.app" → "com.foo.app"
    private static func stripContainerPrefixes(_ name: String) -> String {
        var id = name
        if id.hasPrefix("group.") { id = String(id.dropFirst(6)) }
        let parts = id.split(separator: ".", maxSplits: 1)
        if parts.count == 2 {
            let first = String(parts[0])
            if first.count >= 8, first.count <= 12,
               first.allSatisfy({ $0.isLetter || $0.isNumber }),
               first.uppercased() == first {
                id = String(parts[1])
                if id.hasPrefix("group.") { id = String(id.dropFirst(6)) }
                if id.hasPrefix("groups.") { id = String(id.dropFirst(7)) }
            }
        }
        return id
    }

    private func findMatches(in directory: String, patterns: [String]) -> [String] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: directory) else { return [] }
        var matches: [String] = []

        for item in items where patterns.contains(where: { Self.matchesBoundary(item, $0) }) {
            let path = (directory as NSString).appendingPathComponent(item)
            if !matches.contains(path) {
                matches.append(path)
            }
        }
        return matches
    }
}
