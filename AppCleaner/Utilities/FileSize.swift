import Foundation

enum FileSize {
    static func directorySize(at path: String) -> Int64 {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [],
            errorHandler: nil
        ) else {
            return fileSize(at: path)
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  resourceValues.isDirectory == false,
                  let size = resourceValues.fileSize else {
                continue
            }
            total += Int64(size)
        }
        return total
    }

    static func fileSize(at path: String) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    static func sizeAt(path: String) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            return 0
        }
        return isDir.boolValue ? directorySize(at: path) : fileSize(at: path)
    }

    static func formatted(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
