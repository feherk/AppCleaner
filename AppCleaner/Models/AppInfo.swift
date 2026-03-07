import AppKit
import Foundation

struct AppInfo: Identifiable, Hashable {
    let id: String // bundleIdentifier or path
    let name: String
    let bundleIdentifier: String
    let path: String
    let icon: NSImage
    var bundleSize: Int64
    var totalSize: Int64
    var components: [AppComponent]

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
