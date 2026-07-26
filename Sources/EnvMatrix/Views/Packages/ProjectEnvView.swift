import SwiftUI
import AppKit

public struct ProjectEnvView: View {
    @StateObject var vm = ProjectEnvViewModel()
    @EnvironmentObject private var localization: LocalizationManager

    @State var deleteTarget: ProjectEnvironment?
    @State var showLogSheet: Bool = false
    @State var showRootsSheet: Bool = false
    @State var showBatchDeleteSheet: Bool = false
    @State var showAbandonedCleanupSheet: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            overviewCard
            Divider()
            toolbar
            Divider()
            HSplitView {
                envList
                    .frame(minWidth: 320, idealWidth: 460)
                detailPane
                    .frame(minWidth: 260)
            }
            if let msg = vm.errorMessage {
                errorBanner(msg)
            }
        }
        .navigationTitle(L("projenv.title"))
        .task { await vm.refreshIfNeeded() }
        .sheet(item: $deleteTarget) { target in
            deleteConfirmSheet(target)
        }
        .sheet(isPresented: $showRootsSheet) {
            rootsEditorSheet
        }
        .sheet(isPresented: $showLogSheet) {
            logSheet
        }
        .sheet(isPresented: $showBatchDeleteSheet) {
            batchDeleteConfirmSheet
        }
        .sheet(isPresented: $showAbandonedCleanupSheet) {
            abandonedCleanupSheet
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.title)
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("projenv.title"))
                    .font(.title2.bold())
                HStack(spacing: 6) {
                    Text(String(format: L("projenv.subtitle"), vm.roots.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if vm.scanDuration > 0 {
                        Text(String(format: L("projenv.scannedIn"), vm.scanDuration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()

            statChip(
                value: vm.environments.count,
                label: L("projenv.total"),
                systemImage: "shippingbox"
            )
            statChip(
                text: ByteFormatter.format(vm.totalBytes),
                label: L("projenv.reclaimable"),
                systemImage: "internaldrive"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $vm.kindFilter) {
                ForEach(ProjectEnvKindFilter.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L("projenv.searchPlaceholder"), text: $vm.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 260)

            HStack(spacing: 4) {
                Text(L("projenv.minSize"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $vm.minSizeMB, in: 0...2000, step: 50)
                    .frame(width: 120)
                Text(vm.minSizeMB == 0 ? L("projenv.minSizeOff")
                     : String(format: "≥%.0f MB", vm.minSizeMB))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
            }

            Spacer()

            Menu {
                ForEach(ProjectEnvSortOption.allCases) { opt in
                    Button {
                        vm.sortOption = opt
                    } label: {
                        if vm.sortOption == opt {
                            Label(opt.label, systemImage: "checkmark")
                        } else {
                            Text(opt.label)
                        }
                    }
                }
            } label: {
                Label(
                    String(format: L("projenv.sort.menuLabel"), vm.sortOption.label),
                    systemImage: "arrow.up.arrow.down"
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if !vm.selectedEnvIDs.isEmpty {
                Button {
                    showBatchDeleteSheet = true
                } label: {
                    Label(
                        String(format: L("projenv.toolbar.deleteSelected"),
                               vm.selectedEnvIDs.count),
                        systemImage: "trash"
                    )
                }
            }

            Button {
                showRootsSheet = true
            } label: {
                Label(L("projenv.roots"), systemImage: "folder.badge.gearshape")
            }

            Button {
                Task { await vm.rescan() }
            } label: {
                if vm.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L("projenv.rescan"), systemImage: "arrow.clockwise")
                }
            }
            .disabled(vm.isScanning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - List column

    private var envList: some View {
        Group {
            if vm.isScanning && vm.environments.isEmpty {
                scanningState
            } else if vm.visibleEnvironments.isEmpty {
                emptyState
            } else {
                List(selection: $vm.selectedEnvIDs) {
                    ForEach(vm.visibleEnvironments) { env in
                        row(for: env)
                            .tag(env.id)
                            .contextMenu {
                                Button(L("projenv.action.reveal")) { vm.reveal(env) }
                                Button(L("projenv.action.revealProject")) { vm.revealProject(env) }
                                Button(L("projenv.action.openTerminal")) { vm.openInTerminal(env) }
                                Divider()
                                Button(role: .destructive) {
                                    deleteTarget = env
                                } label: { Text(L("projenv.action.delete")) }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func row(for env: ProjectEnvironment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: env.kind == .venv ? "swift" : "square.stack.3d.up.fill")
                .font(.title3)
                .foregroundStyle(env.kind == .venv ? .green : .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(env.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(env.projectRoot.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormatter.format(env.sizeBytes))
                    .font(.callout.monospacedDigit())
                if env.kind == .venv, let py = env.pythonVersion {
                    Text(py)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if env.kind == .nodeModules, let pm = env.packageManager {
                    Text(pm == .unknown ? "npm?" : pm.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: vm.health(for: env).hex))
                        .frame(width: 6, height: 6)
                    Text(vm.health(for: env).label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if vm.selectedEnvIDs.count > 1 {
            multiSelectionDetail
        } else if let id = vm.selectedEnvIDs.first,
                  let env = vm.environments.first(where: { $0.id == id }) {
            envDetail(env)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(L("projenv.detail.pickHint"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func envDetail(_ env: ProjectEnvironment) -> some View {
        let health = vm.health(for: env)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: env.kind == .venv ? "swift" : "square.stack.3d.up.fill")
                        .font(.largeTitle)
                        .foregroundStyle(env.kind == .venv ? .green : .blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(env.displayTitle)
                            .font(.title3.bold())
                        HStack(spacing: 6) {
                            Text(env.kind.shortLabel)
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                            Text(health.label)
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(hex: health.hex).opacity(0.18), in: Capsule())
                                .foregroundStyle(Color(hex: health.hex))
                        }
                    }
                    Spacer()
                }

                Divider()

                infoRow(L("projenv.field.projectRoot"), env.projectRoot.path)
                infoRow(L("projenv.field.envPath"), env.url.path)
                infoRow(L("projenv.field.size"), ByteFormatter.format(env.sizeBytes))
                if env.kind == .venv, let py = env.pythonVersion {
                    infoRow(L("projenv.field.pythonVersion"), py)
                }
                if env.kind == .nodeModules, let pm = env.packageManager {
                    infoRow(L("projenv.field.packageManager"),
                            pm == .unknown ? L("projenv.pm.unknown") : pm.rawValue)
                }
                if let mtime = env.modifiedAt {
                    infoRow(L("projenv.field.modified"),
                            mtime.formatted(date: .abbreviated, time: .shortened))
                }

                Divider()

                actionButtons(env)
            }
            .padding(20)
        }
    }

    private func actionButtons(_ env: ProjectEnvironment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("projenv.actions")).font(.headline)
            HStack(spacing: 10) {
                Button {
                    vm.reveal(env)
                } label: {
                    Label(L("projenv.action.reveal"), systemImage: "folder")
                }
                Button {
                    vm.openInTerminal(env)
                } label: {
                    Label(L("projenv.action.openTerminal"), systemImage: "terminal")
                }
                if env.kind == .nodeModules {
                    Button {
                        showLogSheet = true
                        Task { await vm.reinstall(env) }
                    } label: {
                        Label(L("projenv.action.reinstall"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(vm.runningOpID != nil)
                }
                Spacer()
                Button(role: .destructive) {
                    deleteTarget = env
                } label: {
                    Label(L("projenv.action.delete"), systemImage: "trash")
                }
            }

            Text(L("projenv.trashHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Convenience: view-facing helpers.
extension ProjectEnvViewModel {
    var hasNoRoots: Bool { roots.isEmpty }
}
