import Foundation

actor ComponentFinder {
    func findComponents(for app: AppInfo) -> [AppComponent] {
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

        // Search locations: (directory, type, patterns)
        let searchSpecs: [(String, ComponentType, [String])] = [
            ("\(home)/Library/Application Support", .applicationSupport, [bundleID, appName]),
            ("\(home)/Library/Caches", .caches, [bundleID, appName]),
            ("\(home)/Library/Logs", .logs, [appName, bundleID]),
            ("\(home)/Library/Saved Application State", .savedState, ["\(bundleID).savedState"]),
            ("\(home)/Library/Containers", .containers, [bundleID]),
            ("\(home)/Library/HTTPStorages", .httpStorages, [bundleID]),
            ("\(home)/Library/WebKit", .webKit, [bundleID]),
            ("\(home)/Library/Application Support/CrashReporter", .crashReports, [bundleID]),
        ]

        for (directory, type, patterns) in searchSpecs {
            guard fm.fileExists(atPath: directory) else { continue }
            for match in findMatches(in: directory, patterns: patterns) {
                let size = FileSize.sizeAt(path: match)
                components.append(AppComponent(path: match, type: type, size: size, isSelected: true))
            }
        }

        // Preferences - plist files
        let prefsDir = "\(home)/Library/Preferences"
        if let items = try? fm.contentsOfDirectory(atPath: prefsDir) {
            for item in items where item.hasPrefix(bundleID) && item.hasSuffix(".plist") {
                let path = (prefsDir as NSString).appendingPathComponent(item)
                let size = FileSize.fileSize(at: path)
                components.append(AppComponent(path: path, type: .preferences, size: size, isSelected: true))
            }
        }

        // Group Containers - partial match
        let groupDir = "\(home)/Library/Group Containers"
        if let items = try? fm.contentsOfDirectory(atPath: groupDir) {
            for item in items where item.localizedCaseInsensitiveContains(bundleID) || item.localizedCaseInsensitiveContains(appName) {
                let path = (groupDir as NSString).appendingPathComponent(item)
                let size = FileSize.sizeAt(path: path)
                components.append(AppComponent(path: path, type: .groupContainers, size: size, isSelected: true))
            }
        }

        // Cookies
        let cookiesDir = "\(home)/Library/Cookies"
        if let items = try? fm.contentsOfDirectory(atPath: cookiesDir) {
            for item in items where item.hasPrefix(bundleID) {
                let path = (cookiesDir as NSString).appendingPathComponent(item)
                let size = FileSize.fileSize(at: path)
                components.append(AppComponent(path: path, type: .cookies, size: size, isSelected: true))
            }
        }

        // Diagnostic Reports
        let diagDirs = [
            "/Library/Logs/DiagnosticReports",
            "\(home)/Library/Logs/DiagnosticReports"
        ]
        for diagDir in diagDirs {
            if let items = try? fm.contentsOfDirectory(atPath: diagDir) {
                for item in items where item.localizedCaseInsensitiveContains(appName) {
                    let path = (diagDir as NSString).appendingPathComponent(item)
                    let size = FileSize.fileSize(at: path)
                    components.append(AppComponent(path: path, type: .crashReports, size: size, isSelected: true))
                }
            }
        }

        return components
    }

    private func findMatches(in directory: String, patterns: [String]) -> [String] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: directory) else { return [] }
        var matches: [String] = []

        for item in items {
            for pattern in patterns {
                if item.localizedCaseInsensitiveCompare(pattern) == .orderedSame
                    || item.hasPrefix(pattern) {
                    let path = (directory as NSString).appendingPathComponent(item)
                    if !matches.contains(path) {
                        matches.append(path)
                    }
                }
            }
        }
        return matches
    }
}
