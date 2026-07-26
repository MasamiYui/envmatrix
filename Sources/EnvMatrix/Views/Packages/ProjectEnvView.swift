import SwiftUI
import AppKit

public struct ProjectEnvView: View {
    @StateObject private var vm = ProjectEnvViewModel()
    @EnvironmentObject private var localization: LocalizationManager

    @State private var deleteTarget: ProjectEnvironment?
    @State private var showLogSheet: Bool = false
    @State private var showRootsSheet: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
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
                List(selection: $vm.selectedEnvID) {
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
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if let env = vm.selectedEnv {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: env.kind == .venv ? "swift" : "square.stack.3d.up.fill")
                        .font(.largeTitle)
                        .foregroundStyle(env.kind == .venv ? .green : .blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(env.displayTitle)
                            .font(.title3.bold())
                        Text(env.kind.shortLabel)
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
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

    // MARK: - Sheets

    private func deleteConfirmSheet(_ env: ProjectEnvironment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                Text(L("projenv.deleteConfirm.title")).font(.title3.bold())
            }
            Text(String(format: L("projenv.deleteConfirm.body"),
                        env.displayTitle,
                        ByteFormatter.format(env.sizeBytes)))
            Text(env.url.path)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)

            HStack {
                Spacer()
                Button(L("projenv.cancel")) { deleteTarget = nil }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    vm.delete(env)
                    deleteTarget = nil
                } label: {
                    Text(L("projenv.deleteConfirm.confirm"))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
    }

    private var rootsEditorSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("projenv.rootsEditor.title")).font(.title3.bold())
            Text(L("projenv.rootsEditor.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(vm.roots, id: \.self) { url in
                    HStack {
                        Image(systemName: "folder")
                        Text(url.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            vm.removeRoot(url)
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 200)
            HStack {
                Button {
                    pickFolder { url in
                        if let url { vm.addRoot(url) }
                    }
                } label: {
                    Label(L("projenv.rootsEditor.add"), systemImage: "plus")
                }
                Spacer()
                Button(L("projenv.done")) {
                    showRootsSheet = false
                    Task { await vm.rescan() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 360)
    }

    private var logSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("projenv.log.title")).font(.title3.bold())
                Spacer()
                if vm.runningOpID != nil {
                    ProgressView().controlSize(.small)
                }
                Button(L("projenv.done")) { showLogSheet = false }
                    .disabled(vm.runningOpID != nil)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(vm.opLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .background(.black.opacity(0.85))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 420)
    }

    // MARK: - Empty / scanning / error

    private var scanningState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(L("projenv.scanning"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(vm.hasNoRoots ? L("projenv.empty.noRoots") : L("projenv.empty.noEnvs"))
                .font(.headline)
            if vm.hasNoRoots {
                Button {
                    showRootsSheet = true
                } label: {
                    Label(L("projenv.rootsEditor.add"), systemImage: "plus")
                }
            } else {
                Button {
                    Task { await vm.rescan() }
                } label: {
                    Label(L("projenv.rescan"), systemImage: "arrow.clockwise")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(msg).font(.callout)
            Spacer()
            Button {
                vm.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.red.opacity(0.12))
    }

    // MARK: - Helpers

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statChip(value: Int, label: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text("\(value)").font(.callout.monospacedDigit().bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }

    private func statChip(text: String, label: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(text).font(.callout.monospacedDigit().bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }

    /// Open an NSOpenPanel restricted to selecting a single directory.
    private func pickFolder(_ completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("projenv.rootsEditor.add")
        panel.begin { response in
            if response == .OK {
                completion(panel.url)
            } else {
                completion(nil)
            }
        }
    }
}

// Convenience: view-facing helpers.
private extension ProjectEnvViewModel {
    var hasNoRoots: Bool { roots.isEmpty }
}
