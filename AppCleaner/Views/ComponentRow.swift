import SwiftUI

struct ComponentRow: View {
    let component: AppComponent
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { component.isSelected },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(component.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(component.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(FileSize.formatted(component.size))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch component.type {
        case .appBundle: return "app.fill"
        case .applicationSupport: return "folder.fill"
        case .caches: return "internaldrive.fill"
        case .preferences: return "gearshape.fill"
        case .logs: return "doc.text.fill"
        case .savedState: return "clock.fill"
        case .containers: return "shippingbox.fill"
        case .groupContainers: return "square.stack.3d.up.fill"
        case .httpStorages: return "network"
        case .webKit: return "globe"
        case .crashReports: return "exclamationmark.triangle.fill"
        case .cookies: return "circle.dotted"
        case .launchAgents: return "arrow.triangle.2.circlepath"
        case .launchDaemons: return "bolt.badge.clock.fill"
        case .privilegedHelpers: return "lock.shield.fill"
        }
    }

    private var iconColor: Color {
        switch component.type {
        case .appBundle: return .blue
        case .caches: return .orange
        case .preferences: return .gray
        case .crashReports: return .red
        case .launchAgents, .launchDaemons, .privilegedHelpers: return .purple
        default: return .secondary
        }
    }
}
