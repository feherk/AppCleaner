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
}
