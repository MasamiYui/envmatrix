import SwiftUI
import AppKit

/// The menu-bar popover: switch the active version of any installed
/// runtime without opening the main window, plus shortcuts into it.
struct MenuBarPanel: View {
    @StateObject private var vm = MenuBarViewModel()
    @ObservedObject private var shims = ShimsPathStatus.shared
    @ObservedObject private var updates = UpdateChecker.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var expanded: Set<RuntimeKind> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            body_
            Divider()
            footer
        }
        .frame(width: 320)
        .task { await vm.refreshIfStale() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .foregroundStyle(.tint)
            Text("EnvMatrix").font(.headline)
            Spacer()
            if vm.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await vm.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(L("common.refresh"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Body

    @ViewBuilder
    private var body_: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if shims.isConfigured == false {
                    warningRow
                }
                if let release = updates.pendingRelease {
                    updateRow(release)
                }
                if vm.items.isEmpty {
                    Text(L("menubar.empty"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                } else {
                    ForEach(vm.items) { item in
                        runtimeRow(item)
                    }
                }
                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 360)
    }

    private var warningRow: some View {
        Button {
            openMainWindow(select: .dashboard)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(L("menubar.pathWarning"))
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func updateRow(_ release: AppRelease) -> some View {
        Button {
            NSWorkspace.shared.open(release.url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                Text(String(format: L("dashboard.attention.update.title"), release.version))
                    .font(.callout)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func runtimeRow(_ item: MenuBarViewModel.Item) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                guard item.isSwitchable else {
                    openMainWindow(select: .devEnv(item.kind))
                    return
                }
                withAnimation(.easeInOut(duration: 0.12)) {
                    if expanded.contains(item.kind) { expanded.remove(item.kind) } else { expanded.insert(item.kind) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: item.kind.iconName)
                        .foregroundStyle(item.kind.brandColor)
                        .frame(width: 18)
                    Text(item.kind.displayName)
                    Spacer(minLength: 4)
                    if vm.switchingKind == item.kind {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(item.active ?? L("dashboard.notSet"))
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if item.isSwitchable {
                        Image(systemName: expanded.contains(item.kind) ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded.contains(item.kind) {
                ForEach(item.versions) { version in
                    Button {
                        Task { await vm.activate(version) }
                    } label: {
                        HStack(spacing: 8) {
                            Group {
                                if version.version == item.active {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: 12, height: 12)
                            Text(version.version).font(.callout.monospaced())
                            if version.isSystem {
                                Text(L("runtime.systemBadge"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 38)
                        .padding(.trailing, 12)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(version.version == item.active)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            menuItem(L("menubar.openDashboard"), "macwindow") { openMainWindow(select: .dashboard) }
            menuItem(L("menubar.search"), "magnifyingglass") {
                openMainWindow(select: nil)
                NotificationCenter.default.post(name: .envMatrixOpenGlobalSearch, object: nil)
            }
            menuItem(L("nav.settings"), "gearshape") { openMainWindow(select: .settings) }
            Divider().padding(.vertical, 4)
            menuItem(L("menubar.quit"), "power") { NSApplication.shared.terminate(nil) }
        }
        .padding(.vertical, 6)
    }

    private func menuItem(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Brings the main window forward (creating nothing new — the app uses a
    /// single WindowGroup) and optionally navigates it.
    private func openMainWindow(select item: NavigationItem?) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain && $0.contentView != nil }) {
            window.makeKeyAndOrderFront(nil)
        }
        if let item {
            NotificationCenter.default.post(name: .envMatrixNavigate, object: item)
        }
    }
}
