import SwiftUI

struct AppListView: View {
    @ObservedObject var viewModel: AppCleanerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: Search + Mode picker
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("Search...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(.quaternary.opacity(0.5))
                .cornerRadius(6)

                Button {
                    Task { await viewModel.scan() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Rescan")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Content
            if viewModel.isScanning {
                VStack {
                    ProgressView("Scanning...")
                        .padding()
                }
                .frame(maxHeight: .infinity)
            } else {
                switch viewModel.viewMode {
                case .apps:
                    appsList
                case .leftovers:
                    leftoversList
                case .cleanDrive:
                    EmptyView()
                }
            }

            Divider()

            Text("AppCleaner v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0") — FK")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }

    private var appsList: some View {
        List(viewModel.filteredApps, selection: Binding<AppInfo?>(
            get: { viewModel.selectedApp },
            set: { app in
                if let app {
                    Task { await viewModel.selectApp(app) }
                }
            }
        )) { app in
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Text(FileSize.formatted(app.totalSize))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 2)
            .tag(app)
        }
    }

    private var leftoversList: some View {
        List(viewModel.filteredLeftovers, selection: Binding<Set<String>>(
            get: { viewModel.selectedLeftovers },
            set: { ids in
                viewModel.selectedLeftovers = ids
                viewModel.selectLeftoversChanged()
            }
        )) { leftover in
            HStack(spacing: 10) {
                Image(nsImage: leftover.icon)
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(leftover.bundleIdentifier)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(FileSize.formatted(leftover.totalSize))
                        if !leftover.note.isEmpty && leftover.note != "Not installed" {
                            Text("—")
                            Text(leftover.note)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 2)
            .tag(leftover.id)
        }
    }
}
