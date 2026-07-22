import SwiftUI

enum ViewMode: String, CaseIterable {
    case apps = "Applications"
    case leftovers = "Leftovers"
    case cleanDrive = "Clean Drive"
}

@MainActor
class AppCleanerViewModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var leftovers: [LeftoverGroup] = []
    @Published var cleanupCategories: [CleanupCategory] = []
    @Published var selectedApp: AppInfo?
    @Published var selectedLeftovers: Set<String> = []
    @Published var isScanning = false
    @Published var isLoadingComponents = false
    @Published var isScanningDrive = false
    @Published var needsFullDiskAccess = false
    @Published var searchText = ""
    @Published var viewMode: ViewMode = .apps

    private let scanner = AppScanner()
    private let componentFinder = ComponentFinder()
    private let leftoverScanner = LeftoverScanner()
    private let driveScanner = DriveCleanerScanner()

    var filteredApps: [AppInfo] {
        if searchText.isEmpty { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var filteredLeftovers: [LeftoverGroup] {
        if searchText.isEmpty { return leftovers }
        return leftovers.filter { $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText) }
    }

    var selectedLeftoverGroups: [LeftoverGroup] {
        leftovers.filter { selectedLeftovers.contains($0.id) }
    }

    var selectedComponents: [AppComponent] {
        switch viewMode {
        case .apps: return selectedApp?.components ?? []
        case .leftovers: return selectedLeftoverGroups.flatMap(\.components)
        case .cleanDrive: return []
        }
    }

    var selectedSize: Int64 {
        selectedComponents.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }

    func scan() async {
        isScanning = true

        let installedIDs = await scanner.collectBundleIDs()

        async let scannedApps = scanner.scanApplications()
        async let scannedLeftovers = leftoverScanner.scanLeftovers(installedBundleIDs: installedIDs)

        apps = await scannedApps
        leftovers = await scannedLeftovers

        isScanning = false
    }

    func scanDrive() async {
        isScanningDrive = true
        needsFullDiskAccess = await driveScanner.needsFullDiskAccess()
        cleanupCategories = await driveScanner.scan()
        isScanningDrive = false
    }

    func loadCategoryItems(at index: Int) async {
        let cat = cleanupCategories[index]
        if cat.id == "trash" {
            // Use Finder AppleScript for Trash (TCC blocks direct access)
            let items = await driveScanner.scanTrashItems()
            cleanupCategories[index].items = items
        } else {
            let items = await driveScanner.scanItems(for: cat.paths)
            cleanupCategories[index].items = items
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func selectApp(_ app: AppInfo) async {
        selectedApp = app
        selectedLeftovers.removeAll()
        isLoadingComponents = true

        if app.components.isEmpty {
            let components = await componentFinder.findComponents(for: app)
            let totalSize = components.reduce(0) { $0 + $1.size }

            if let index = apps.firstIndex(where: { $0.id == app.id }) {
                apps[index].components = components
                apps[index].totalSize = totalSize
                selectedApp = apps[index]
            }
        }

        isLoadingComponents = false
    }

    func selectLeftoversChanged() {
        selectedApp = nil
    }

    func toggleComponent(_ component: AppComponent) {
        switch viewMode {
        case .apps:
            guard var app = selectedApp,
                  let compIndex = app.components.firstIndex(where: { $0.id == component.id }) else { return }
            app.components[compIndex].isSelected.toggle()
            selectedApp = app
            if let appIndex = apps.firstIndex(where: { $0.id == app.id }) { apps[appIndex] = app }
        case .leftovers:
            for idx in leftovers.indices where selectedLeftovers.contains(leftovers[idx].id) {
                if let compIndex = leftovers[idx].components.firstIndex(where: { $0.id == component.id }) {
                    leftovers[idx].components[compIndex].isSelected.toggle()
                    break
                }
            }
        case .cleanDrive:
            break
        }
    }

    func toggleSelectAll(_ selectAll: Bool) {
        switch viewMode {
        case .apps:
            guard var app = selectedApp else { return }
            for i in app.components.indices { app.components[i].isSelected = selectAll }
            selectedApp = app
            if let appIndex = apps.firstIndex(where: { $0.id == app.id }) { apps[appIndex] = app }
        case .leftovers:
            for idx in leftovers.indices where selectedLeftovers.contains(leftovers[idx].id) {
                for i in leftovers[idx].components.indices { leftovers[idx].components[i].isSelected = selectAll }
            }
        case .cleanDrive:
            break
        }
    }

    func uninstallSelected() async {
        let selected = selectedComponents.filter(\.isSelected)

        // User-level items go to the Trash. Root-owned system items (launchd
        // jobs, privileged helpers) can't be trashed by the user, so they're
        // removed together via a single administrator-privileged shell call.
        for component in selected where !component.requiresAdmin {
            let path = component.path
            // Try NSWorkspace first; fall back to Finder AppleScript for protected locations (/Applications)
            do {
                try await NSWorkspace.shared.recycle([URL(fileURLWithPath: path)])
            } catch {
                let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
                let script = NSAppleScript(source: "tell application \"Finder\" to delete (POSIX file \"\(escaped)\" as alias)")
                var scriptError: NSDictionary?
                script?.executeAndReturnError(&scriptError)
            }
        }

        let privileged = selected.filter(\.requiresAdmin)
        if !privileged.isEmpty {
            removePrivileged(privileged)
        }

        switch viewMode {
        case .apps:
            if let app = selectedApp, let index = apps.firstIndex(where: { $0.id == app.id }) { apps.remove(at: index) }
            selectedApp = nil
        case .leftovers:
            leftovers.removeAll { selectedLeftovers.contains($0.id) }
            selectedLeftovers.removeAll()
        case .cleanDrive:
            break
        }
    }

    /// Removes root-owned components (launchd jobs, privileged helpers) with a
    /// single administrator prompt. LaunchDaemons/LaunchAgents are unloaded via
    /// `launchctl bootout` before their plists are deleted so the running
    /// process stops immediately rather than lingering until reboot.
    private func removePrivileged(_ components: [AppComponent]) {
        var commands: [String] = []
        for component in components {
            if let label = component.launchdLabel {
                let domain = component.type == .launchDaemons ? "system" : "gui/$(id -u)"
                commands.append("/bin/launchctl bootout \(domain)/\(label) 2>/dev/null || true")
            }
            commands.append("/bin/rm -rf \(shellQuote(component.path))")
        }
        let shellCommand = commands.joined(separator: "; ")

        // Embed the shell command in an AppleScript string literal.
        let appleScriptLiteral = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(appleScriptLiteral)\" with administrator privileges"
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
    }

    /// Single-quotes a path for safe use in a POSIX shell command.
    private func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func performCleanup() async {
        let fm = FileManager.default
        for cat in cleanupCategories where cat.isSelected && cat.size > 0 {
            if cat.id == "trash" {
                // Empty trash via Finder AppleScript (works without FDA)
                let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
                var error: NSDictionary?
                script?.executeAndReturnError(&error)
            } else if cat.id == "downloads" {
                // Move installers to trash
                for path in cat.paths {
                    let url = URL(fileURLWithPath: path)
                    do {
                        try await NSWorkspace.shared.recycle([url])
                    } catch {
                        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
                        let script = NSAppleScript(source: "tell application \"Finder\" to delete (POSIX file \"\(escaped)\" as alias)")
                        var scriptError: NSDictionary?
                        script?.executeAndReturnError(&scriptError)
                    }
                }
            } else {
                // Delete contents but keep the directory
                for path in cat.paths {
                    if let items = try? fm.contentsOfDirectory(atPath: path) {
                        for item in items {
                            let itemPath = (path as NSString).appendingPathComponent(item)
                            try? fm.removeItem(atPath: itemPath)
                        }
                    }
                }
            }
        }

        // Animate selected categories to zero
        withAnimation(.easeInOut(duration: 0.6)) {
            for i in cleanupCategories.indices where cleanupCategories[i].isSelected {
                cleanupCategories[i].size = 0
                cleanupCategories[i].paths = []
                cleanupCategories[i].isSelected = false
            }
        }

        // Wait for animation, then rescan for accurate values
        try? await Task.sleep(nanoseconds: 800_000_000)
        await scanDrive()
    }

    func switchMode(_ mode: ViewMode) {
        viewMode = mode
        selectedApp = nil
        selectedLeftovers.removeAll()
        searchText = ""

        if mode == .cleanDrive && cleanupCategories.isEmpty {
            Task { await scanDrive() }
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = AppCleanerViewModel()

    var body: some View {
        Group {
            if viewModel.viewMode == .cleanDrive {
                CleanDriveView(viewModel: viewModel)
                    .frame(minWidth: 500, minHeight: 500)
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            modePicker
                        }
                    }
            } else {
                NavigationSplitView {
                    AppListView(viewModel: viewModel)
                        .navigationSplitViewColumnWidth(min: 250, ideal: 300)
                } detail: {
                    ComponentListView(viewModel: viewModel)
                }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        modePicker
                    }
                }
            }
        }
        .task {
            await viewModel.scan()
        }
    }

    private var modePicker: some View {
        Picker("", selection: Binding(
            get: { viewModel.viewMode },
            set: { viewModel.switchMode($0) }
        )) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 300)
    }
}
