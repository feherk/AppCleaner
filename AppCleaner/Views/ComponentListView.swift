import SwiftUI

struct ComponentListView: View {
    @ObservedObject var viewModel: AppCleanerViewModel
    @State private var showConfirmation = false

    private var hasSelection: Bool {
        viewModel.selectedApp != nil || viewModel.selectedLeftover != nil
    }

    private var headerIcon: NSImage? {
        switch viewModel.viewMode {
        case .apps:
            return viewModel.selectedApp?.icon
        case .leftovers:
            return viewModel.selectedLeftover?.icon
        case .cleanDrive:
            return nil
        }
    }

    private var headerTitle: String {
        switch viewModel.viewMode {
        case .apps:
            return viewModel.selectedApp?.name ?? ""
        case .leftovers:
            return viewModel.selectedLeftover?.bundleIdentifier ?? ""
        case .cleanDrive:
            return ""
        }
    }

    private var headerSubtitle: String {
        switch viewModel.viewMode {
        case .apps:
            return viewModel.selectedApp?.bundleIdentifier ?? ""
        case .leftovers:
            return viewModel.selectedLeftover?.note ?? "Leftover files"
        case .cleanDrive:
            return ""
        }
    }

    var body: some View {
        if hasSelection {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    if let icon = headerIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 48, height: 48)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(headerTitle)
                            .font(.title2.bold())
                        Text(headerSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding()

                Divider()

                if viewModel.isLoadingComponents {
                    VStack {
                        ProgressView("Finding related files...")
                            .padding()
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    // Select all toggle
                    HStack {
                        let components = viewModel.selectedComponents
                        let allSelected = !components.isEmpty && components.allSatisfy(\.isSelected)
                        Toggle("Select All", isOn: Binding(
                            get: { allSelected },
                            set: { viewModel.toggleSelectAll($0) }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(viewModel.selectedComponents.count) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)

                    Divider()

                    // Component list
                    List {
                        ForEach(Dictionary(grouping: viewModel.selectedComponents, by: \.type).sorted(by: { $0.key.rawValue < $1.key.rawValue }), id: \.key) { type, components in
                            Section(type.rawValue) {
                                ForEach(components) { component in
                                    ComponentRow(
                                        component: component,
                                        onToggle: { viewModel.toggleComponent(component) }
                                    )
                                }
                            }
                        }
                    }
                }

                Divider()

                // Footer
                HStack {
                    Text("Total selected: **\(FileSize.formatted(viewModel.selectedSize))**")

                    Spacer()

                    Button(viewModel.viewMode == .leftovers ? "Clean" : "Uninstall") {
                        showConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(viewModel.selectedComponents.filter(\.isSelected).isEmpty)
                }
                .padding()
            }
            .alert("Confirm", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Move to Trash", role: .destructive) {
                    Task { await viewModel.uninstallSelected() }
                }
            } message: {
                Text("Move \(viewModel.selectedComponents.filter(\.isSelected).count) items (\(FileSize.formatted(viewModel.selectedSize))) to Trash?")
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: viewModel.viewMode == .leftovers ? "trash" : "app.dashed")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text(viewModel.viewMode == .leftovers ? "Select a leftover to clean" : "Select an application")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
