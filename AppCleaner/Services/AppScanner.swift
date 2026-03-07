import AppKit
import Foundation

actor AppScanner {
    func scanApplications() -> [AppInfo] {
        let fm = FileManager.default
        var apps: [AppInfo] = []
        var seenBundleIDs = Set<String>()

        let directories = [
            "/Applications",
            NSHomeDirectory() + "/Applications"
        ]

        for directory in directories {
            scanDirectory(directory, depth: 0, fm: fm, apps: &apps, seenBundleIDs: &seenBundleIDs)
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// All installed bundle IDs (fast, no size calculation)
    func collectBundleIDs() -> Set<String> {
        let fm = FileManager.default
        var ids = Set<String>()

        let directories = [
            "/Applications",
            NSHomeDirectory() + "/Applications"
        ]

        for directory in directories {
            collectIDs(in: directory, depth: 0, fm: fm, ids: &ids)
        }

        return ids
    }

    /// Recursively scan for .app bundles, up to 3 levels deep
    /// Does NOT recurse into .app bundles themselves
    private func scanDirectory(_ directory: String, depth: Int, fm: FileManager, apps: inout [AppInfo], seenBundleIDs: inout Set<String>) {
        guard depth <= 3 else { return }
        guard let contents = try? fm.contentsOfDirectory(atPath: directory) else { return }

        for item in contents {
            let fullPath = (directory as NSString).appendingPathComponent(item)

            if item.hasSuffix(".app") {
                if let appInfo = appInfoFrom(path: fullPath),
                   !seenBundleIDs.contains(appInfo.bundleIdentifier) {
                    seenBundleIDs.insert(appInfo.bundleIdentifier)
                    apps.append(appInfo)
                }
                // Do NOT recurse into .app bundles
            } else {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                    scanDirectory(fullPath, depth: depth + 1, fm: fm, apps: &apps, seenBundleIDs: &seenBundleIDs)
                }
            }
        }
    }

    /// Fast ID collection - same traversal but skips size calculation
    private func collectIDs(in directory: String, depth: Int, fm: FileManager, ids: inout Set<String>) {
        guard depth <= 3 else { return }
        guard let contents = try? fm.contentsOfDirectory(atPath: directory) else { return }

        for item in contents {
            let fullPath = (directory as NSString).appendingPathComponent(item)

            if item.hasSuffix(".app") {
                let plistPath = (fullPath as NSString).appendingPathComponent("Contents/Info.plist")
                if let plist = NSDictionary(contentsOfFile: plistPath),
                   let bid = plist["CFBundleIdentifier"] as? String, !bid.isEmpty {
                    ids.insert(bid)
                }
            } else {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                    collectIDs(in: fullPath, depth: depth + 1, fm: fm, ids: &ids)
                }
            }
        }
    }

    private func appInfoFrom(path: String) -> AppInfo? {
        let plistPath = (path as NSString).appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOfFile: plistPath) else { return nil }

        let bundleID = plist["CFBundleIdentifier"] as? String ?? ""
        let name = plist["CFBundleName"] as? String
            ?? plist["CFBundleDisplayName"] as? String
            ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension

        guard !bundleID.isEmpty else { return nil }

        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)

        let bundleSize = FileSize.directorySize(at: path)

        return AppInfo(
            id: bundleID,
            name: name,
            bundleIdentifier: bundleID,
            path: path,
            icon: icon,
            bundleSize: bundleSize,
            totalSize: bundleSize,
            components: []
        )
    }
}
