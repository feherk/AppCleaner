import SwiftUI

struct CleanDriveView: View {
    @ObservedObject var viewModel: AppCleanerViewModel
    @State private var showConfirmation = false
    @State private var expandedCategory: String? = nil

    private var totalSelected: Int64 {
        viewModel.cleanupCategories.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }

    private var totalAll: Int64 {
        viewModel.cleanupCategories.reduce(0) { $0 + $1.size }
    }

    private var confirmationMessage: String {
        var parts = ["Remove \(FileSize.formatted(totalSelected)) of files?"]
        if viewModel.cleanupCategories.contains(where: { $0.isSelected && $0.id == "trash" }) {
            parts.append("The Trash will be emptied.")
        }
        parts.append("Files are deleted permanently. Administrator access may be requested for system-owned files.")
        return parts.joined(separator: "\n\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 30)

            // Big size display
            Text(FileSize.formatted(totalSelected))
                .font(.system(size: 42, weight: .light))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.6), value: totalSelected)

            Text("Ready for Cleanup")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            // Color bar
            if totalAll > 0 {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(viewModel.cleanupCategories.filter { $0.size > 0 }) { cat in
                            let fraction = CGFloat(cat.size) / CGFloat(totalAll)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorFor(cat.color).opacity(cat.isSelected ? 1.0 : 0.3))
                                .frame(width: max(4, geo.size.width * fraction))
                        }
                    }
                    .animation(.easeInOut(duration: 0.6), value: viewModel.cleanupCategories.map(\.size))
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(.horizontal, 40)
                .padding(.top, 16)
            }

            Spacer().frame(height: 24)

            // Category list
            if viewModel.isScanningDrive {
                VStack {
                    ProgressView("Scanning drive...")
                        .padding()
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.cleanupCategories.indices, id: \.self) { index in
                        let cat = viewModel.cleanupCategories[index]
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedCategory == cat.id },
                                set: { isExpanded in
                                    if isExpanded && cat.size == 0 { return }
                                    expandedCategory = isExpanded ? cat.id : nil
                                    if isExpanded && cat.items == nil {
                                        Task { await viewModel.loadCategoryItems(at: index) }
                                    }
                                }
                            )
                        ) {
                            if let items = cat.items, !items.isEmpty {
                                ForEach(items.prefix(50)) { item in
                                    HStack(spacing: 8) {
                                        Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                                            .foregroundStyle(.secondary)
                                            .font(.system(size: 11))
                                            .frame(width: 16)

                                        Text(item.name)
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                            .truncationMode(.middle)

                                        Spacer()

                                        if let date = item.modDate {
                                            Text(date, style: .date)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.tertiary)
                                        }

                                        Text(FileSize.formatted(item.size))
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 1)
                                }
                            } else if cat.items != nil {
                                Text("No files found")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Toggle("", isOn: $viewModel.cleanupCategories[index].isSelected)
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                    .disabled(cat.size == 0)

                                Circle()
                                    .fill(colorFor(cat.color))
                                    .frame(width: 10, height: 10)

                                Text(cat.name)
                                    .font(.system(size: 14))

                                Spacer()

                                Text(FileSize.formatted(cat.size))
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(cat.size > 0 ? .primary : .tertiary)
                                    .contentTransition(.numericText())
                                    .animation(.easeInOut(duration: 0.6), value: cat.size)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }

            // FDA warning
            if viewModel.needsFullDiskAccess {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Grant Full Disk Access for complete results (Trash, etc.)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Settings...") {
                        viewModel.openFullDiskAccessSettings()
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            // Clean Up button
            HStack {
                Spacer()
                Button("Clean Up") {
                    showConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(totalSelected == 0)
                Spacer()
            }
            .padding(.top)

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .padding(.bottom, 8)
            }
        }
        .alert("Confirm Cleanup", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clean Up", role: .destructive) {
                Task { await viewModel.performCleanup() }
            }
        } message: {
            Text(confirmationMessage)
        }
        .onChange(of: viewModel.isScanningDrive) { _, scanning in
            // Collapse any open category on rescan so a stale item list
            // doesn't linger with a spinner that never resolves.
            if scanning { expandedCategory = nil }
        }
    }

    private func colorFor(_ name: String) -> Color {
        switch name {
        case "orange": return .orange
        case "yellow": return .yellow
        case "pink": return .pink
        case "blue": return .blue
        case "cyan": return .cyan
        case "indigo": return .indigo
        case "green": return .green
        case "purple": return .purple
        default: return .gray
        }
    }
}
