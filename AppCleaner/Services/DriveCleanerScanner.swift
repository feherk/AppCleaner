import Foundation

struct CleanupFileItem: Identifiable {
    let id: String  // full path
    let name: String
    let size: Int64
    let modDate: Date?
    let isDirectory: Bool
}

struct CleanupCategory: Identifiable {
    let id: String
    let name: String
    let color: String // SF Symbol color name
    var size: Int64
    var paths: [String]
    var isSelected: Bool
    var items: [CleanupFileItem]?  // nil = not yet scanned
}

actor DriveCleanerScanner {
    /// Check if we likely lack Full Disk Access by testing .Trash readability
    func needsFullDiskAccess() -> Bool {
        let home = NSHomeDirectory()
        let trashDir = "\(home)/.Trash"
        let fm = FileManager.default
        // .Trash exists but we can't list its contents → FDA missing
        guard fm.fileExists(atPath: trashDir) else { return false }
        guard let items = try? fm.contentsOfDirectory(atPath: trashDir) else { return true }
        // Has items but directorySize returns 0 → can't read file sizes
        if !items.isEmpty && FileSize.directorySize(at: trashDir) == 0 { return true }
        return false
    }

    func scan() -> [CleanupCategory] {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        var categories: [CleanupCategory] = []

        // 1. Log files
        var logDirs = [
            "\(home)/Library/Logs",
            "/Library/Logs",
            "/private/var/log",
            "\(home)/Library/Biome",
            "\(home)/Library/DuetExpertCenter",
            "\(home)/Library/Metadata",
        ]
        // Add Containers log dirs
        let containersDir = "\(home)/Library/Containers"
        if let containers = try? fm.contentsOfDirectory(atPath: containersDir) {
            for container in containers {
                let logsPath = (containersDir as NSString).appendingPathComponent(container + "/Data/Library/Logs")
                if fm.fileExists(atPath: logsPath) {
                    logDirs.append(logsPath)
                }
            }
        }
        let (logSize, logPaths) = scanDirectories(logDirs)
        categories.append(CleanupCategory(id: "logs", name: "Log files", color: "orange", size: logSize, paths: logPaths, isSelected: logSize > 0))

        // 2. Cache files
        var cacheDirs = [
            "\(home)/Library/Caches",
            "/Library/Caches",
        ]
        // Add Containers cache dirs
        if let containers = try? fm.contentsOfDirectory(atPath: containersDir) {
            for container in containers {
                let cachePath = (containersDir as NSString).appendingPathComponent(container + "/Data/Library/Caches")
                if fm.fileExists(atPath: cachePath) {
                    cacheDirs.append(cachePath)
                }
            }
        }
        // Add user temp files (/private/var/folders)
        if let userTempDir = NSTemporaryDirectory() as String? {
            let parentDir = (userTempDir as NSString).deletingLastPathComponent
            let cDir = (parentDir as NSString).appendingPathComponent("C")
            if fm.fileExists(atPath: cDir) { cacheDirs.append(cDir) }
            cacheDirs.append(userTempDir)
        }
        let (cacheSize, cachePaths) = scanDirectories(cacheDirs)
        categories.append(CleanupCategory(id: "caches", name: "Cache files", color: "yellow", size: cacheSize, paths: cachePaths, isSelected: cacheSize > 0))

        // 3. Trash
        var trashSize: Int64 = 0
        var trashPaths: [String] = []
        let trashDir = "\(home)/.Trash"
        let trashSizeCalc = FileSize.directorySize(at: trashDir)
        if trashSizeCalc > 0 {
            trashSize = trashSizeCalc
            trashPaths = [trashDir]
        }
        categories.append(CleanupCategory(id: "trash", name: "Trash", color: "pink", size: trashSize, paths: trashPaths, isSelected: trashSize > 0))

        // 4. Browser data (caches only, not history/bookmarks)
        var browserPaths: [String] = []
        var browserSize: Int64 = 0
        let browserDirs = [
            "\(home)/Library/Caches/Google/Chrome",
            "\(home)/Library/Caches/com.google.Chrome",
            "\(home)/Library/Caches/Firefox",
            "\(home)/Library/Caches/com.brave.Browser",
            "\(home)/Library/Caches/com.operasoftware.Opera",
            "\(home)/Library/Safari/LocalStorage",
        ]
        for dir in browserDirs {
            if FileManager.default.fileExists(atPath: dir) {
                let s = FileSize.directorySize(at: dir)
                if s > 0 { browserSize += s; browserPaths.append(dir) }
            }
        }
        categories.append(CleanupCategory(id: "browser", name: "Browser data", color: "blue", size: browserSize, paths: browserPaths, isSelected: false))

        // 5. Mail cache
        let mailDirs = [
            "\(home)/Library/Mail/V10",
            "\(home)/Library/Containers/com.apple.mail/Data/Library/Caches",
        ]
        var mailPaths: [String] = []
        var mailSize: Int64 = 0
        for dir in mailDirs {
            if FileManager.default.fileExists(atPath: dir) {
                let s = FileSize.directorySize(at: dir)
                if s > 0 { mailSize += s; mailPaths.append(dir) }
            }
        }
        categories.append(CleanupCategory(id: "mail", name: "Mail cache", color: "cyan", size: mailSize, paths: mailPaths, isSelected: false))

        // 6. Xcode derived data
        let xcodeDirs = [
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/Library/Developer/Xcode/Archives",
            "\(home)/Library/Developer/Xcode/iOS DeviceSupport",
        ]
        var xcodePaths: [String] = []
        var xcodeSize: Int64 = 0
        for dir in xcodeDirs {
            if FileManager.default.fileExists(atPath: dir) {
                let s = FileSize.directorySize(at: dir)
                if s > 0 { xcodeSize += s; xcodePaths.append(dir) }
            }
        }
        categories.append(CleanupCategory(id: "xcode", name: "Xcode junk", color: "indigo", size: xcodeSize, paths: xcodePaths, isSelected: false))

        // 7. iOS device backups
        let backupDir = "\(home)/Library/Application Support/MobileSync/Backup"
        let (backupSize, backupPaths) = scanDirectories([backupDir])
        categories.append(CleanupCategory(id: "backups", name: "iOS device backups", color: "green", size: backupSize, paths: backupPaths, isSelected: false))

        // 8. Old downloads (DMG, PKG in Downloads)
        let downloadsDir = "\(home)/Downloads"
        var dlPaths: [String] = []
        var dlSize: Int64 = 0
        if let items = try? FileManager.default.contentsOfDirectory(atPath: downloadsDir) {
            for item in items {
                let lower = item.lowercased()
                if lower.hasSuffix(".dmg") || lower.hasSuffix(".pkg") || lower.hasSuffix(".iso") {
                    let path = (downloadsDir as NSString).appendingPathComponent(item)
                    let s = FileSize.sizeAt(path: path)
                    if s > 0 { dlSize += s; dlPaths.append(path) }
                }
            }
        }
        categories.append(CleanupCategory(id: "downloads", name: "Installers (DMG/PKG)", color: "purple", size: dlSize, paths: dlPaths, isSelected: false))

        return categories
    }

    func scanItems(for paths: [String]) -> [CleanupFileItem] {
        let fm = FileManager.default
        var items: [CleanupFileItem] = []

        for dir in paths {
            guard let children = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for child in children {
                let fullPath = (dir as NSString).appendingPathComponent(child)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

                let size: Int64
                if isDir.boolValue {
                    size = FileSize.directorySize(at: fullPath)
                } else {
                    size = FileSize.sizeAt(path: fullPath)
                }
                guard size > 0 else { continue }

                let attrs = try? fm.attributesOfItem(atPath: fullPath)
                let modDate = attrs?[.modificationDate] as? Date

                items.append(CleanupFileItem(
                    id: fullPath,
                    name: child,
                    size: size,
                    modDate: modDate,
                    isDirectory: isDir.boolValue
                ))
            }
        }

        return items.sorted { $0.size > $1.size }
    }

    private func scanDirectories(_ dirs: [String]) -> (Int64, [String]) {
        var totalSize: Int64 = 0
        var paths: [String] = []
        let fm = FileManager.default

        for dir in dirs {
            guard fm.fileExists(atPath: dir) else { continue }
            let size = FileSize.directorySize(at: dir)
            if size > 0 {
                totalSize += size
                paths.append(dir)
            }
        }

        return (totalSize, paths)
    }
}
