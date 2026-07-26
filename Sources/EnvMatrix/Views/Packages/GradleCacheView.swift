import SwiftUI
import AppKit

struct GradleCacheView: View {
    @ObservedObject var vm: GradleCacheViewModel

    enum Section: String, CaseIterable, Identifiable {
        case artifacts
        case wrappers
        var id: String { rawValue }
        var label: String {
            switch self {
            case .artifacts: return L("gradleCache.section.artifacts")
            case .wrappers:  return L("gradleCache.section.wrappers")
            }
        }
    }

    @State private var section: Section = .artifacts
    @State private var showBatchDeleteConfirm: Bool = false
    @State private var singleDelete: SingleDelete? = nil

    fileprivate enum SingleDelete: Identifiable {
        case artifact(GradleArtifact)
        case wrapper(GradleWrapperDist)
        var id: String {
            switch self {
            case .artifact(let a): return "a-\(a.id)"
            case .wrapper(let w):  return "w-\(w.id)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            statsBar
            Divider()
            Picker("", selection: $section) {
                ForEach(Section.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            toolbar
            Divider()
            content
            if let msg = vm.errorMessage {
                errorBanner(msg)
            }
        }
        .confirmationDialog(
            L("gradleCache.confirmDelete.title"),
            isPresented: $showBatchDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(L("gradleCache.confirmDelete.confirm"), role: .destructive) {
                Task { await performBatchDelete() }
            }
            Button(L("runtime.cancel"), role: .cancel) {}
        } message: {
            Text(String(
                format: L("gradleCache.confirmDelete.body"),
                selectedCountInCurrentSection
            ))
        }
        .alert(item: $singleDelete) { target in
            switch target {
            case .artifact(let a):
                return Alert(
                    title: Text(L("gradleCache.confirmDelete.title")),
                    message: Text(String(
                        format: L("gradleCache.confirmDelete.body"),
                        1
                    ) + "\n\(a.group):\(a.artifact):\(a.version)"),
                    primaryButton: .destructive(
                        Text(L("gradleCache.confirmDelete.confirm"))
                    ) {
                        Task { await vm.deleteArtifacts([a.id]) }
                    },
                    secondaryButton: .cancel(Text(L("runtime.cancel")))
                )
            case .wrapper(let w):
                return Alert(
                    title: Text(L("gradleCache.confirmDelete.title")),
                    message: Text(String(
                        format: L("gradleCache.confirmDelete.body"),
                        1
                    ) + "\n\(w.versionLabel)"),
                    primaryButton: .destructive(
                        Text(L("gradleCache.confirmDelete.confirm"))
                    ) {
                        Task { await vm.deleteWrappers([w.id]) }
                    },
                    secondaryButton: .cancel(Text(L("runtime.cancel")))
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.orange)
            Text("Gradle")
                .font(.title3.bold())
            Spacer()
            if vm.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Stats

    private var statsBar: some View {
        HStack(spacing: 10) {
            statCard(
                title: L("gradleCache.total.artifacts"),
                bytes: vm.artifactsTotalBytes,
                icon: "shippingbox.fill",
                tint: .orange
            )
            statCard(
                title: L("gradleCache.total.wrappers"),
                bytes: vm.wrappersTotalBytes,
                icon: "wrench.and.screwdriver.fill",
                tint: .blue
            )
            statCard(
                title: L("gradleCache.total.combined"),
                bytes: vm.grandTotalBytes,
                icon: "sum",
                tint: .secondary
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func statCard(
        title: String,
        bytes: Int64,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Self.formatBytes(bytes))
                    .font(.headline.monospacedDigit())
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    section == .artifacts
                        ? L("gradleCache.searchPlaceholder.artifacts")
                        : L("gradleCache.searchPlaceholder.wrappers"),
                    text: section == .artifacts
                        ? $vm.artifactSearch
                        : $vm.wrapperSearch
                )
                .textFieldStyle(.plain)
                if !currentSearchText.isEmpty {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .frame(maxWidth: .infinity)

            sortMenu

            Button(role: .destructive) {
                showBatchDeleteConfirm = true
            } label: {
                Label(
                    L("gradleCache.action.deleteSelected"),
                    systemImage: "trash"
                )
                .font(.caption)
            }
            .disabled(selectedCountInCurrentSection == 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var sortMenu: some View {
        Menu {
            Picker("", selection: sortBinding) {
                ForEach(GradleSortOption.allCases) { opt in
                    Text(opt.label).tag(opt)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(currentSortLabel, systemImage: "arrow.up.arrow.down")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.artifacts.isEmpty && vm.wrappers.isEmpty && !vm.isScanning {
            emptyState
        } else {
            switch section {
            case .artifacts: artifactsList
            case .wrappers:  wrappersList
            }
        }
    }

    // MARK: - Artifacts list

    private var artifactsList: some View {
        List(vm.visibleArtifacts, selection: $vm.selectedArtifactIDs) { art in
            artifactRow(art)
                .tag(art.id)
                .contextMenu {
                    Button(L("gradleCache.action.reveal")) {
                        NSWorkspace.shared.activateFileViewerSelecting([art.url])
                    }
                    Button(role: .destructive) {
                        singleDelete = .artifact(art)
                    } label: {
                        Text(L("gradleCache.action.delete"))
                    }
                }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func artifactRow(_ art: GradleArtifact) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(art.group):\(art.artifact)")
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("v\(art.version)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.formatBytes(art.sizeBytes))
                    .font(.caption.monospacedDigit())
                if let m = art.modifiedAt {
                    Text(Self.relativeString(from: m))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Wrappers list

    private var wrappersList: some View {
        List(vm.visibleWrappers, selection: $vm.selectedWrapperIDs) { w in
            wrapperRow(w)
                .tag(w.id)
                .contextMenu {
                    Button(L("gradleCache.action.reveal")) {
                        NSWorkspace.shared.activateFileViewerSelecting([w.url])
                    }
                    Button(role: .destructive) {
                        singleDelete = .wrapper(w)
                    } label: {
                        Text(L("gradleCache.action.delete"))
                    }
                }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func wrapperRow(_ w: GradleWrapperDist) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(w.versionLabel)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.formatBytes(w.sizeBytes))
                    .font(.caption.monospacedDigit())
                if let m = w.modifiedAt {
                    Text(Self.relativeString(from: m))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L("gradleCache.empty.title"))
                .font(.title2.bold())
            Text(L("gradleCache.empty.hint"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                if let url = URL(string: "https://gradle.org") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label(
                    L("gradleCache.empty.openWebsite"),
                    systemImage: "safari"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Error banner

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
            Spacer()
            Button {
                vm.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.red.opacity(0.08))
    }

    // MARK: - Bindings / helpers

    private var currentSearchText: String {
        section == .artifacts ? vm.artifactSearch : vm.wrapperSearch
    }

    private func clearSearch() {
        switch section {
        case .artifacts: vm.artifactSearch = ""
        case .wrappers:  vm.wrapperSearch = ""
        }
    }

    private var sortBinding: Binding<GradleSortOption> {
        switch section {
        case .artifacts:
            return Binding(
                get: { vm.artifactSort },
                set: { vm.artifactSort = $0 }
            )
        case .wrappers:
            return Binding(
                get: { vm.wrapperSort },
                set: { vm.wrapperSort = $0 }
            )
        }
    }

    private var currentSortLabel: String {
        (section == .artifacts ? vm.artifactSort : vm.wrapperSort).label
    }

    private var selectedCountInCurrentSection: Int {
        section == .artifacts
            ? vm.selectedArtifactIDs.count
            : vm.selectedWrapperIDs.count
    }

    private func performBatchDelete() async {
        switch section {
        case .artifacts:
            await vm.deleteArtifacts(vm.selectedArtifactIDs)
        case .wrappers:
            await vm.deleteWrappers(vm.selectedWrapperIDs)
        }
    }

    // MARK: - Formatters

    private static func formatBytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static func relativeString(from date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
