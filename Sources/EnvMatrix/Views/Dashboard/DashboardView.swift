import SwiftUI

public struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var navigator: AppNavigator

    public init() {}

    /// Adaptive grid: cards wrap naturally as the window resizes.
    private let runtimeColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16, alignment: .top)
    ]
    private let overviewColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 16, alignment: .top)
    ]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                runtimesSection
                overviewSection
            }
            .padding(24)
        }
        .background(backgroundLayer.ignoresSafeArea())
        .navigationTitle(L("dashboard.title"))
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.hardRefresh() }
    }

    // MARK: - Header

    private var header: some View {
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
                    Task { await viewModel.hardRefresh() }
                } label: {
                    Label(L("dashboard.refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            HStack(spacing: 12) {
                SummaryChip(
                    icon: "circle.grid.3x3.fill",
                    tint: .accentColor,
                    label: L("dashboard.activeRuntimes"),
                    value: "\(activeRuntimeCount)/\(viewModel.runtimes.count)"
                )
                SummaryChip(
                    icon: "sparkles",
                    tint: .purple,
                    label: L("dashboard.skills"),
                    value: "\(viewModel.skillsCount)"
                )
                SummaryChip(
                    icon: "bolt.horizontal.fill",
                    tint: .orange,
                    label: L("dashboard.mcpServers"),
                    value: "\(viewModel.mcpCount)"
                )
                SummaryChip(
                    icon: "internaldrive.fill",
                    tint: .teal,
                    label: L("dashboard.storage"),
                    value: Self.formatBytes(viewModel.storageBytes)
                )
            }
        }
    }

    // MARK: - Runtimes

    private var runtimesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                icon: "cpu",
                title: L("dashboard.section.runtimes")
            )
            LazyVGrid(columns: runtimeColumns, spacing: 16) {
                ForEach(viewModel.runtimes) { snapshot in
                    RuntimeCard(snapshot: snapshot) {
                        navigator.openRuntime(snapshot.kind)
                    }
                }
            }
        }
    }

    // MARK: - Overview (skills / mcp / storage)

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
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
            }
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.08),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var activeRuntimeCount: Int {
        viewModel.runtimes.filter { $0.activeVersion != nil }.count
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
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

// MARK: - Summary Chip

private struct SummaryChip: View {
    let icon: String
    let tint: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - Runtime Card

private struct RuntimeCard: View {
    let snapshot: DashboardViewModel.RuntimeSnapshot
    let action: () -> Void
    @State private var isHovering = false

    private var isInstalled: Bool { snapshot.activeVersion != nil }

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
        .accessibilityLabel(Text("\(snapshot.kind.displayName) \(snapshot.activeVersion ?? L("dashboard.notSet"))"))
        .accessibilityHint(Text(L("dashboard.card.openHint")))
        .accessibilityAddTraits(.isButton)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BrandBadge(kind: snapshot.kind, isDimmed: !isInstalled)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.kind.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(L("dashboard.runtimeSuffix"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if snapshot.isSystemDefault {
                    StatusBadge(text: L("dashboard.system"), tint: .orange)
                } else if isInstalled {
                    StatusBadge(text: L("dashboard.managed"), tint: .green)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let version = snapshot.activeVersion {
                    Text("v")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(version)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(L("dashboard.notSet"))
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovering ? 1.0 : 0.5)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
        .shadow(color: shadowColor, radius: isHovering ? 10 : 4, x: 0, y: isHovering ? 6 : 2)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
            if isInstalled {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                snapshot.kind.brandColor.opacity(0.12),
                                snapshot.kind.brandColor.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }

    private var borderColor: Color {
        isInstalled
            ? snapshot.kind.brandColor.opacity(0.28)
            : Color.primary.opacity(0.06)
    }

    private var shadowColor: Color {
        isInstalled
            ? snapshot.kind.brandColor.opacity(0.20)
            : Color.black.opacity(0.05)
    }
}

// MARK: - Brand Badge

private struct BrandBadge: View {
    let kind: RuntimeKind
    let isDimmed: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDimmed ? AnyShapeStyle(Color.gray.opacity(0.18)) : AnyShapeStyle(kind.brandGradient))
                .frame(width: 40, height: 40)
                .shadow(color: isDimmed ? .clear : kind.brandColor.opacity(0.35), radius: 4, x: 0, y: 2)
            Image(systemName: kind.iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(isDimmed ? Color.secondary : Color.white)
        }
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule(style: .continuous))
            .foregroundStyle(tint)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 0.5)
            )
    }
}

// MARK: - Info Card (Skills / MCP / Storage)

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
