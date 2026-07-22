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
    @Published var errorMessage: String?

    private let scanner = AppScanner()
    private let componentFinder = ComponentFinder()
    private let leftoverScanner = LeftoverScanner()
    private let driveScanner = DriveCleanerScanner()
    private var installedBundleIDs: Set<String> = []

    var filteredApps: [AppInfo] {
        if searchText.isEmpty { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var filteredLeftovers: [LeftoverGroup] {
        if searchText.isEmpty { return leftovers }
        return leftovers.filter {
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
                || $0.note.localizedCaseInsensitiveContains(searchText)
        }
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
        installedBundleIDs = installedIDs

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
            let components = await componentFinder.findComponents(for: app, installedBundleIDs: installedBundleIDs)
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
        var failedPaths = Set<String>()

        // User-level items go to the Trash. Root-owned system items (launchd
        // jobs, privileged helpers) can't be trashed by the user, so they're
        // removed together via a single administrator-privileged shell call.
        for component in selected where !component.requiresAdmin {
            // Stop user-level launchd jobs first so the process doesn't
            // linger until logout after its plist is gone.
            if let label = component.launchdLabel {
                await Task.detached { ScriptRunner.bootoutUserJob(label: label) }.value
            }

            let path = component.path
            var removed = false
            // Try NSWorkspace first; fall back to Finder AppleScript for protected locations (/Applications)
            do {
                try await NSWorkspace.shared.recycle([URL(fileURLWithPath: path)])
                removed = true
            } catch {
                removed = await Task.detached { ScriptRunner.finderDelete(path: path) }.value
            }
            if !removed { failedPaths.insert(path) }
        }

        let privileged = selected.filter(\.requiresAdmin)
        if !privileged.isEmpty {
            let command = Self.privilegedRemovalCommand(for: privileged, uid: getuid())
            let ok = await Task.detached { ScriptRunner.runPrivileged(command) }.value
            if !ok {
                for component in privileged { failedPaths.insert(component.path) }
                errorMessage = "Administrator authorization failed or was cancelled — system items were not removed."
            }
        }

        if !failedPaths.isEmpty && errorMessage == nil {
            errorMessage = "\(failedPaths.count) item(s) could not be moved to the Trash."
        }

        // Update the lists to reflect only what was actually removed.
        switch viewMode {
        case .apps:
            guard let app = selectedApp else { break }
            let bundleRemoved = selected.contains { $0.type == .appBundle } && !failedPaths.contains(app.path)
            if bundleRemoved {
                apps.removeAll { $0.id == app.id }
                selectedApp = nil
            } else if let index = apps.firstIndex(where: { $0.id == app.id }) {
                // App bundle kept (deselected or failed) — refresh its components
                apps[index].components = []
                await selectApp(apps[index])
            }
        case .leftovers:
            let removedPaths = Set(selected.map(\.path)).subtracting(failedPaths)
            for idx in leftovers.indices {
                leftovers[idx].components.removeAll { removedPaths.contains($0.path) }
                leftovers[idx].totalSize = leftovers[idx].components.reduce(0) { $0 + $1.size }
            }
            leftovers.removeAll { $0.components.isEmpty }
            selectedLeftovers = selectedLeftovers.filter { id in leftovers.contains { $0.id == id } }
        case .cleanDrive:
            break
        }
    }

    /// Builds the single admin shell call that removes root-owned components.
    /// LaunchDaemons/LaunchAgents are unloaded via `launchctl bootout` before
    /// their plists are deleted so the running process stops immediately rather
    /// than lingering until reboot. The uid is resolved here because the
    /// privileged script runs as root, where `$(id -u)` would be 0.
    private static func privilegedRemovalCommand(for components: [AppComponent], uid: uid_t) -> String {
        var commands: [String] = []
        for component in components {
            if let label = component.launchdLabel {
                let domain = component.type == .launchDaemons ? "system" : "gui/\(uid)"
                commands.append("/bin/launchctl bootout \(domain)/\(label) 2>/dev/null || true")
            }
            commands.append("/bin/rm -rf \(ScriptRunner.shellQuote(component.path))")
        }
        return commands.joined(separator: "; ")
    }

    func performCleanup() async {
        // User-level pass runs on the scanner actor so big deletions don't
        // block the UI; system-owned leftovers come back for one admin call.
        let outcome = await driveScanner.cleanup(categories: cleanupCategories)

        if !outcome.adminPaths.isEmpty {
            let command = Self.adminCleanupCommand(for: outcome.adminPaths)
            let ok = await Task.detached { ScriptRunner.runPrivileged(command) }.value
            if !ok {
                errorMessage = "Administrator authorization failed or was cancelled — some system files were not removed."
            }
        }

        if !outcome.failedUserPaths.isEmpty {
            let shown = outcome.failedUserPaths.prefix(3)
                .map { ($0 as NSString).lastPathComponent }
                .joined(separator: ", ")
            let note = "\(outcome.failedUserPaths.count) item(s) could not be removed (\(shown), …)."
            errorMessage = errorMessage.map { $0 + "\n\n" + note } ?? note
        }

        // Animate selected categories to zero
        withAnimation(.easeInOut(duration: 0.6)) {
            for i in cleanupCategories.indices where cleanupCategories[i].isSelected {
                cleanupCategories[i].size = 0
                cleanupCategories[i].paths = []
                cleanupCategories[i].items = nil
                cleanupCategories[i].isSelected = false
            }
        }

        // Wait for animation, then rescan for accurate values
        try? await Task.sleep(nanoseconds: 800_000_000)
        await scanDrive()
    }

    /// Admin removal for cleanup leftovers. The Trash is special-cased: its
    /// contents are removed, never the .Trash directory itself.
    private static func adminCleanupCommand(for paths: [String]) -> String {
        paths.map { path in
            if path.hasSuffix("/.Trash") {
                return "/usr/bin/find \(ScriptRunner.shellQuote(path)) -mindepth 1 -maxdepth 1 -exec /bin/rm -rf {} +"
            }
            return "/bin/rm -rf \(ScriptRunner.shellQuote(path))"
        }.joined(separator: "; ")
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
        .alert("AppCleaner", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
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
