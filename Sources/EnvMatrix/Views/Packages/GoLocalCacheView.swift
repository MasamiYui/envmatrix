import SwiftUI
import AppKit

struct GoLocalCacheView: View {
    @ObservedObject var vm: GoLocalCacheViewModel
    @State private var expandedIDs: Set<String> = []
    @State private var deleteTarget: DeleteTarget? = nil

    private enum DeleteTarget: Identifiable {
        case module(GoModuleArtifact)
        case version(GoModuleArtifact, GoModuleVersion)
        var id: String {
            switch self {
            case .module(let a): return "mod-\(a.id)"
            case .version(_, let v): return "ver-\(v.id)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            searchBar
            Divider()
            content
            if let msg = vm.errorMessage {
                errorBanner(msg)
            }
        }
        .alert(item: $deleteTarget) { target in
            switch target {
            case .module(let art):
                return Alert(
                    title: Text(String(format: L("goRepo.cache.confirmDelete"), art.modulePath)),
                    message: Text(String(
                        format: L("goRepo.cache.confirmDeleteMessage"),
                        GoLocalCacheViewModel.formatSize(art.totalSizeBytes)
                    )),
                    primaryButton: .destructive(Text(L("runtime.uninstall"))) {
                        vm.deleteModule(art)
                    },
                    secondaryButton: .cancel(Text(L("runtime.cancel")))
                )
            case .version(let art, let v):
                return Alert(
                    title: Text(String(
                        format: L("goRepo.cache.confirmDeleteVersion"),
                        art.modulePath, v.version
                    )),
                    message: Text(String(
                        format: L("goRepo.cache.confirmDeleteMessage"),
                        GoLocalCacheViewModel.formatSize(v.sizeBytes)
                    )),
                    primaryButton: .destructive(Text(L("runtime.uninstall"))) {
                        vm.deleteVersion(art, v)
                    },
                    secondaryButton: .cancel(Text(L("runtime.cancel")))
                )
            }
        }
    }

    // MARK: - Summary

    private var summaryBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.cachePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 10) {
                    Text(String(
                        format: L("goRepo.cache.countFormat"),
                        vm.artifacts.count
                    ))
                    .font(.caption2.bold())
                    Text(String(
                        format: L("goRepo.cache.totalSizeFormat"),
                        GoLocalCacheViewModel.formatSize(vm.totalSizeBytes)
                    ))
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            sortMenu
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var sortMenu: some View {
        Menu {
            Picker("", selection: $vm.sortMode) {
                Text(L("goRepo.cache.sortByName")).tag(GoModuleSortMode.name)
                Text(L("goRepo.cache.sortBySize")).tag(GoModuleSortMode.size)
                Text(L("goRepo.cache.sortByModified")).tag(GoModuleSortMode.modified)
            }
            Divider()
            Toggle(L("goRepo.cache.ascending"), isOn: $vm.sortAscending)
        } label: {
            Label(sortLabel, systemImage: "arrow.up.arrow.down")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var sortLabel: String {
        switch vm.sortMode {
        case .name: return L("goRepo.cache.sortByName")
        case .size: return L("goRepo.cache.sortBySize")
        case .modified: return L("goRepo.cache.sortByModified")
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L("goRepo.cache.searchPlaceholder"), text: $vm.searchText)
                .textFieldStyle(.plain)
            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
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
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text(L("goRepo.cache.loading"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !vm.cacheExists {
            emptyView(
                icon: "exclamationmark.folder",
                title: L("goRepo.cache.notFound.title"),
                subtitle: String(
                    format: L("goRepo.cache.notFound.subtitle"),
                    vm.cachePath
                )
            )
        } else if vm.filteredArtifacts.isEmpty {
            emptyView(
                icon: "tray",
                title: L("goRepo.cache.empty.title"),
                subtitle: L("goRepo.cache.empty.subtitle")
            )
        } else {
            moduleList
        }
    }

    private var moduleList: some View {
        List {
            ForEach(vm.filteredArtifacts) { art in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedIDs.contains(art.id) },
                        set: { open in
                            if open { expandedIDs.insert(art.id) }
                            else { expandedIDs.remove(art.id) }
                        }
                    )
                ) {
                    ForEach(art.versions) { v in
                        versionRow(art, v)
                    }
                } label: {
                    moduleRow(art)
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func moduleRow(_ art: GoModuleArtifact) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(art.modulePath)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(String(
                        format: L("goRepo.cache.versionCountFormat"),
                        art.versions.count
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Text(GoLocalCacheViewModel.formatSize(art.totalSizeBytes))
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                revealInFinder(art.versions.first?.path.deletingLastPathComponent())
            } label: {
                Image(systemName: "folder")
            }
            .help(L("runtime.revealInFinder"))
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                deleteTarget = .module(art)
            } label: {
                Image(systemName: "trash")
            }
            .help(L("goRepo.cache.deleteAll"))
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func versionRow(_ art: GoModuleArtifact, _ v: GoModuleVersion) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(v.version)
                    .font(.system(.body, design: .monospaced))
                if let m = v.modifiedAt {
                    Text(dateFormatter.string(from: m))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(GoLocalCacheViewModel.formatSize(v.sizeBytes))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button {
                revealInFinder(v.path)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                deleteTarget = .version(art, v)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.leading, 20)
        .padding(.vertical, 2)
    }

    // MARK: - Empty / Error

    private func emptyView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.bold())
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(8)
        .background(Color.red.opacity(0.08))
    }

    // MARK: - Utils

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    private func revealInFinder(_ url: URL?) {
        guard let url = url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
