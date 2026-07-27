import SwiftUI

struct DashboardOverviewSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var navigator: AppNavigator

    private let overviewColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 16, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardOverviewSectionHeader(
                icon: "square.grid.2x2.fill",
                title: L("dashboard.section.overview")
            )
            LazyVGrid(columns: overviewColumns, spacing: 16) {
                InfoCard(
                    icon: "sparkles",
                    tint: .purple,
                    title: L("dashboard.skills"),
                    primary: "\(viewModel.skillsCount)",
                    secondary: L("dashboard.installed"),
                    action: { navigator.select(.aiSkills) }
                )
                InfoCard(
                    icon: "bolt.horizontal.fill",
                    tint: .orange,
                    title: L("dashboard.mcpServers"),
                    primary: "\(viewModel.mcpCount)",
                    secondary: L("dashboard.configured"),
                    action: { navigator.select(.aiMCP) }
                )
                InfoCard(
                    icon: "internaldrive.fill",
                    tint: .teal,
                    title: L("dashboard.storage"),
                    primary: Self.formatBytes(viewModel.storageBytes),
                    secondary: L("dashboard.storage.subtitle"),
                    action: { navigator.select(.settings) }
                )
                ContainerOverviewCard()
            }
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct DashboardOverviewSectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

private struct InfoCard: View {
    let icon: String
    let tint: Color
    let title: String
    let primary: String
    let secondary: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            cardBody
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
            #if canImport(AppKit)
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
            #endif
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title) \(primary)"))
        .accessibilityHint(Text(L("dashboard.card.openHint")))
        .accessibilityAddTraits(.isButton)
    }

    private var cardBody: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.62)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: tint.opacity(0.35), radius: 4, x: 0, y: 2)
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(primary)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .opacity(isHovering ? 1.0 : 0.5)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
        )
        .shadow(color: tint.opacity(isHovering ? 0.22 : 0.10), radius: isHovering ? 10 : 4, x: 0, y: isHovering ? 6 : 2)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}
