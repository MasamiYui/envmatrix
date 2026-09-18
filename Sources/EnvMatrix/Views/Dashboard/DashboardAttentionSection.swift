import SwiftUI
import AppKit

/// "Needs attention" list at the top of the Dashboard. Each row is an
/// actionable problem: shims not on PATH, an oversized package cache, a
/// newer EnvMatrix release. Shows a single green row when nothing needs
/// doing, so the section is never silently empty.
struct DashboardAttentionSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var shims = ShimsPathStatus.shared
    @ObservedObject private var updates = UpdateChecker.shared
    @EnvironmentObject private var navigator: AppNavigator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardOverviewSectionHeader(
                icon: "exclamationmark.circle.fill",
                title: L("dashboard.section.attention")
            )
            VStack(spacing: 0) {
                if items.isEmpty {
                    allClearRow
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 44) }
                        row(item)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 0.5)
            )
        }
        .onAppear { shims.check() }
    }

    // MARK: - Items

    private struct Item: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let detail: String
        let actionTitle: String
        let action: () -> Void
        var isBusy: Bool = false
    }

    private var items: [Item] {
        var result: [Item] = []

        if let file = shims.writtenRcFile {
            result.append(Item(
                id: "shims-done", icon: "checkmark.circle.fill", tint: .green,
                title: L("shims.banner.done.title").replacingOccurrences(of: "%@", with: file.kind.displayName),
                detail: L("shims.banner.done.body"),
                actionTitle: L("shims.banner.reveal"),
                action: { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            ))
        } else if shims.isConfigured == false {
            let rc = shims.targetRcDisplayName
            result.append(Item(
                id: "shims", icon: "terminal.fill", tint: .orange,
                title: L("dashboard.attention.shims.title"),
                detail: String(format: L("dashboard.attention.shims.detail"), rc),
                actionTitle: String(format: L("dashboard.attention.shims.action"), rc),
                action: { shims.addToShellRc() },
                isBusy: shims.isWriting
            ))
        }

        for pkg in viewModel.packages where pkg.needsAttention {
            let nav = pkg.kind.navigationItem
            result.append(Item(
                id: "cache-\(pkg.kind.rawValue)", icon: nav.systemImage, tint: nav.tint,
                title: String(format: L("dashboard.attention.cache.title"), nav.displayName, Self.bytes(pkg.cacheBytes)),
                detail: String(format: L("dashboard.attention.cache.detail"),
                               Self.bytes(DashboardViewModel.cleanupThresholdBytes), nav.displayName),
                actionTitle: L("dashboard.attention.cache.action"),
                action: { navigator.select(nav) }
            ))
        }

        if let release = updates.pendingRelease {
            result.append(Item(
                id: "update", icon: "arrow.down.circle.fill", tint: .blue,
                title: String(format: L("dashboard.attention.update.title"), release.version),
                detail: String(format: L("dashboard.attention.update.detail"), updates.currentVersion),
                actionTitle: L("dashboard.attention.update.action"),
                action: { NSWorkspace.shared.open(release.url) }
            ))
        }
        return result
    }

    // MARK: - Rows

    private func row(_ item: Item) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundStyle(item.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: item.action) {
                if item.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Text(item.actionTitle)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(item.isBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var allClearRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("dashboard.attention.allClear"))
                    .font(.headline)
                Text(String(format: L("dashboard.attention.allClear.detail"),
                            Self.bytes(DashboardViewModel.cleanupThresholdBytes)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private static func bytes(_ value: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: value)
    }
}
