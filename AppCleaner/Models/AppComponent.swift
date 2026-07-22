import Foundation

enum ComponentType: String, CaseIterable {
    case appBundle = "App Bundle"
    case applicationSupport = "Application Support"
    case caches = "Caches"
    case preferences = "Preferences"
    case logs = "Logs"
    case savedState = "Saved State"
    case containers = "Containers"
    case groupContainers = "Group Containers"
    case httpStorages = "HTTP Storage"
    case webKit = "WebKit"
    case crashReports = "Crash Reports"
    case cookies = "Cookies"
    case launchAgents = "Launch Agents"
    case launchDaemons = "Launch Daemons"
    case privilegedHelpers = "Privileged Helper Tools"
}

struct AppComponent: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let type: ComponentType
    let size: Int64
    var isSelected: Bool

    var name: String {
        (path as NSString).lastPathComponent
    }

    /// True for root-owned system locations that cannot be moved to the Trash
    /// by the current user and require administrator privileges to remove.
    var requiresAdmin: Bool {
        !path.hasPrefix(NSHomeDirectory()) &&
            (path.hasPrefix("/Library/") || path.hasPrefix("/System/"))
    }

    /// launchd label for a LaunchDaemon/LaunchAgent plist (filename without `.plist`).
    var launchdLabel: String? {
        guard type == .launchDaemons || type == .launchAgents else { return nil }
        let file = (path as NSString).lastPathComponent
        return file.hasSuffix(".plist") ? String(file.dropLast(6)) : file
    }
}
