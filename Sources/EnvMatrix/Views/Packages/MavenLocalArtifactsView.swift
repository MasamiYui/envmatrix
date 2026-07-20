import SwiftUI
import AppKit

struct MavenLocalArtifactsView: View {
    @ObservedObject var vm: MavenLocalRepositoryViewModel
    @State private var expandedIDs: Set<String> = []
    @State private var deleteTarget: DeleteTarget? = nil

    private enum DeleteTarget: Identifiable {
        case artifact(MavenArtifact)
        case version(MavenArtifact, MavenArtifactVersion)
        var id: String {
            switch self {
            case .artifact(let a): return "art-\(a.id)"
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
            case .artifact(let art):
                return Alert(
                    title: Text(String(format: L("mavenRepo.artifact.confirmDelete"), art.id)),
                    message: Text(String(
                        format: L("mavenRepo.artifact.confirmDeleteMessage"),
                        MavenLocalRepositoryViewModel.formatSize(art.totalSizeBytes)
                    )),
                    primaryButton: .destructive(Text(L("runtime.uninstall"))) {
                        vm.deleteArtifact(art)
                    },
                    secondaryButton: .cancel(Text(L("runtime.cancel")))
                )
            case .version(let art, let v):
                return Alert(
                    title: Text(String(
                        format: L("mavenRepo.artifact.confirmDeleteVersion"),
                        art.id, v.version
                    )),
                    message: Text(String(
                        format: L("mavenRepo.artifact.confirmDeleteMessage"),
                        MavenLocalRepositoryViewModel.formatSize(v.sizeBytes)
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
                Text(vm.repositoryPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 10) {
                    Text(String(
                        format: L("mavenRepo.artifact.countFormat"),
                        vm.artifacts.count
                    ))
                    .font(.caption2.bold())
                    Text(String(
                        format: L("mavenRepo.artifact.totalSizeFormat"),
                        MavenLocalRepositoryViewModel.formatSize(vm.totalSizeBytes)
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
                Text(L("mavenRepo.artifact.sortByName")).tag(MavenArtifactSortMode.name)
                Text(L("mavenRepo.artifact.sortBySize")).tag(MavenArtifactSortMode.size)
                Text(L("mavenRepo.artifact.sortByModified")).tag(MavenArtifactSortMode.modified)
            }
            Divider()
            Toggle(L("mavenRepo.artifact.ascending"), isOn: $vm.sortAscending)
        } label: {
            Label(sortLabel, systemImage: "arrow.up.arrow.down")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var sortLabel: String {
        switch vm.sortMode {
        case .name: return L("mavenRepo.artifact.sortByName")
        case .size: return L("mavenRepo.artifact.sortBySize")
        case .modified: return L("mavenRepo.artifact.sortByModified")
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L("mavenRepo.artifact.searchPlaceholder"), text: $vm.searchText)
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
                Text(L("mavenRepo.artifact.loading"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !vm.repositoryExists {
            emptyView(
                icon: "exclamationmark.folder",
                title: L("mavenRepo.artifact.notFound.title"),
                subtitle: String(
                    format: L("mavenRepo.artifact.notFound.subtitle"),
                    vm.repositoryPath
                )
            )
        } else if vm.filteredArtifacts.isEmpty {
            emptyView(
                icon: "tray",
                title: L("mavenRepo.artifact.empty.title"),
                subtitle: L("mavenRepo.artifact.empty.subtitle")
            )
        } else {
            artifactList
        }
    }

    private var artifactList: some View {
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
                    artifactRow(art)
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func artifactRow(_ art: MavenArtifact) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(art.artifactId)
                    .font(.headline)
                Text(art.groupId)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(String(
                        format: L("mavenRepo.artifact.versionCountFormat"),
                        art.versions.count
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Text(MavenLocalRepositoryViewModel.formatSize(art.totalSizeBytes))
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
                deleteTarget = .artifact(art)
            } label: {
                Image(systemName: "trash")
            }
            .help(L("mavenRepo.artifact.deleteAll"))
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func versionRow(_ art: MavenArtifact, _ v: MavenArtifactVersion) -> some View {
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
            Text(MavenLocalRepositoryViewModel.formatSize(v.sizeBytes))
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
