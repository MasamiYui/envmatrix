import SwiftUI
import AppKit

// MARK: - Overview card, multi-selection detail & bulk sheets

extension ProjectEnvView {

    // MARK: Overview card

    @ViewBuilder
    var overviewCard: some View {
        HStack(spacing: 12) {
            overviewBlock(
                title: L("projenv.overview.total"),
                value: "\(vm.environments.count)",
                systemImage: "shippingbox"
            )
            overviewBlock(
                title: L("projenv.overview.reclaimable"),
                value: ByteFormatter.format(vm.totalBytes),
                systemImage: "internaldrive"
            )
            overviewBlock(
                title: L("projenv.overview.abandonedCount"),
                value: "\(vm.abandonedEnvironments.count)",
                systemImage: "clock.arrow.circlepath",
                tint: Color(hex: ProjectEnvHealth.abandoned.hex)
            )
            overviewBlock(
                title: L("projenv.overview.abandonedSize"),
                value: ByteFormatter.format(vm.abandonedTotalBytes),
                systemImage: "trash",
                tint: Color(hex: ProjectEnvHealth.abandoned.hex)
            )

            Spacer()

            Button {
                showAbandonedCleanupSheet = true
            } label: {
                Label(
                    L("projenv.overview.cleanAbandoned"),
                    systemImage: "sparkles"
                )
            }
            .disabled(vm.abandonedEnvironments.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    private func overviewBlock(
        title: String,
        value: String,
        systemImage: String,
        tint: Color = .accentColor
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.callout.monospacedDigit().bold())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }

    // MARK: Multi-selection detail

    @ViewBuilder
    var multiSelectionDetail: some View {
        let selected = vm.environments.filter { vm.selectedEnvIDs.contains($0.id) }
        let totalBytes = selected.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
        let previewCount = 10

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: L("projenv.multi.title"),
                                    selected.count,
                                    ByteFormatter.format(totalBytes)))
                            .font(.title3.bold())
                        Text(L("projenv.multi.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(selected.prefix(previewCount))) { env in
                        HStack(spacing: 6) {
                            Image(systemName: env.kind == .venv
                                  ? "swift" : "square.stack.3d.up.fill")
                                .foregroundStyle(env.kind == .venv ? .green : .blue)
                            Text(env.url.path)
                                .font(.footnote.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(ByteFormatter.format(env.sizeBytes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if selected.count > previewCount {
                        Text(String(format: L("projenv.multi.moreItems"),
                                    selected.count - previewCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        showBatchDeleteSheet = true
                    } label: {
                        Label(L("projenv.multi.deleteSelected"), systemImage: "trash")
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .padding(20)
        }
    }

    // MARK: Batch delete sheet

    var batchDeleteConfirmSheet: some View {
        let selected = vm.environments.filter { vm.selectedEnvIDs.contains($0.id) }
        let totalBytes = selected.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
        let previewCount = 5

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                Text(L("projenv.batchDelete.title")).font(.title3.bold())
            }
            Text(String(format: L("projenv.batchDelete.body"),
                        selected.count,
                        ByteFormatter.format(totalBytes)))

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(selected.prefix(previewCount))) { env in
                    Text(env.url.path)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if selected.count > previewCount {
                    Text(String(format: L("projenv.batchDelete.morePaths"),
                                selected.count - previewCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(L("projenv.trashHint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(L("projenv.cancel")) { showBatchDeleteSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    let ids = vm.selectedEnvIDs
                    Task {
                        await vm.deleteMany(ids)
                        await MainActor.run { showBatchDeleteSheet = false }
                    }
                } label: {
                    Text(L("projenv.batchDelete.confirm"))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 520)
    }

    // MARK: Abandoned cleanup sheet

    var abandonedCleanupSheet: some View {
        let targets = vm.abandonedEnvironments
        let totalBytes = vm.abandonedTotalBytes
        let previewCount = 5

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                    .font(.title2)
                Text(L("projenv.abandonedCleanup.title")).font(.title3.bold())
            }
            Text(String(format: L("projenv.abandonedCleanup.body"),
                        targets.count,
                        ByteFormatter.format(totalBytes)))

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(targets.prefix(previewCount))) { env in
                    Text(env.url.path)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if targets.count > previewCount {
                    Text(String(format: L("projenv.abandonedCleanup.morePaths"),
                                targets.count - previewCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(L("projenv.trashHint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(L("projenv.cancel")) { showAbandonedCleanupSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    Task {
                        await vm.deleteAllAbandoned()
                        await MainActor.run { showAbandonedCleanupSheet = false }
                    }
                } label: {
                    Text(L("projenv.abandonedCleanup.confirm"))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(targets.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 520)
    }
}

// MARK: - Color(hex:) helper

extension Color {
    /// Initialise from a "#RRGGBB" (or "RRGGBB") string. Falls back to grey
    /// when the input cannot be parsed, so callers never crash on bad data.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else {
            self = Color.gray
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

// MARK: - Sheets, empty / scanning / error states & chip helpers

extension ProjectEnvView {

    func deleteConfirmSheet(_ env: ProjectEnvironment) -> some View {
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

    var rootsEditorSheet: some View {
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
            Toggle(L("projenv.rootsEditor.includeXcode"),
                   isOn: $vm.includeXcodeDerivedData)
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

    var logSheet: some View {
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

    var scanningState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(L("projenv.scanning"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyState: some View {
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

    func errorBanner(_ msg: String) -> some View {
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

    func statChip(value: Int, label: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text("\(value)").font(.callout.monospacedDigit().bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }

    func statChip(text: String, label: String, systemImage: String) -> some View {
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
    func pickFolder(_ completion: @escaping (URL?) -> Void) {
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
