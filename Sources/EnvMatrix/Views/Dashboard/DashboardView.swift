import SwiftUI

public struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @EnvironmentObject private var localization: LocalizationManager

    public init() {}

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("dashboard.title"))
                            .font(.largeTitle.bold())
                        Text(L("dashboard.subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Label(L("dashboard.refresh"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.runtimes) { snapshot in
                        DashboardCardView(
                            icon: Self.icon(for: snapshot.kind),
                            title: "\(snapshot.kind.displayName) \(L("dashboard.runtimeSuffix"))",
                            subtitle: "\(L("dashboard.current")): \(snapshot.activeVersion ?? L("dashboard.notSet"))",
                            badge: snapshot.isSystemDefault ? L("dashboard.system") : nil
                        )
                    }
                    DashboardCardView(
                        icon: "sparkles",
                        title: L("dashboard.skills"),
                        subtitle: "\(viewModel.skillsCount) \(L("dashboard.installed"))"
                    )
                    DashboardCardView(
                        icon: "bolt.horizontal",
                        title: L("dashboard.mcpServers"),
                        subtitle: "\(viewModel.mcpCount) \(L("dashboard.configured"))"
                    )
                    DashboardCardView(
                        icon: "internaldrive",
                        title: L("dashboard.storage"),
                        subtitle: Self.formatBytes(viewModel.storageBytes)
                    )
                }
            }
            .padding()
        }
        .navigationTitle(L("dashboard.title"))
        .id(localization.language)
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
    }

    private static func icon(for kind: RuntimeKind) -> String {
        switch kind {
        case .node: return "n.square"
        case .python: return "p.square"
        case .java: return "j.square"
        case .go: return "g.square"
        case .rust: return "r.square"
        case .ruby: return "diamond.fill"
        case .php: return "chevron.left.forwardslash.chevron.right"
        case .deno: return "pawprint.fill"
        case .bun: return "leaf.fill"
        case .dotnet: return "n.circle.fill"
        case .erlang: return "antenna.radiowaves.left.and.right"
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct DashboardCardView: View {
    let icon: String
    let title: String
    let subtitle: String
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
                if let badge = badge {
                    Text(badge)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                        .foregroundStyle(.orange)
                }
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}
