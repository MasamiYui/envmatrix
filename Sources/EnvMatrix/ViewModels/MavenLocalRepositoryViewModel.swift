import Foundation

public enum MavenArtifactSortMode: String, CaseIterable, Identifiable {
    case name
    case size
    case modified
    public var id: String { rawValue }
}

@MainActor
public final class MavenLocalRepositoryViewModel: ObservableObject {
    @Published public var artifacts: [MavenArtifact] = []
    @Published public var totalSizeBytes: Int64 = 0
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var searchText: String = ""
    @Published public var sortMode: MavenArtifactSortMode = .name
    @Published public var sortAscending: Bool = true
    @Published public var repositoryExists: Bool = false
    @Published public var repositoryPath: String = ""

    private let service: MavenLocalRepositoryService

    public init(service: MavenLocalRepositoryService = DefaultMavenLocalRepositoryService()) {
        self.service = service
        self.repositoryPath = service.repositoryURL.path
        self.repositoryExists = service.repositoryExists
    }

    /// Filtered + sorted view for the UI.
    public var filteredArtifacts: [MavenArtifact] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [MavenArtifact]
        if q.isEmpty {
            filtered = artifacts
        } else {
            filtered = artifacts.filter { art in
                art.groupId.lowercased().contains(q)
                    || art.artifactId.lowercased().contains(q)
                    || art.versions.contains { $0.version.lowercased().contains(q) }
            }
        }
        return sorted(filtered)
    }

    private func sorted(_ items: [MavenArtifact]) -> [MavenArtifact] {
        let asc = sortAscending
        switch sortMode {
        case .name:
            return items.sorted { a, b in
                let cmp = a.id.localizedCaseInsensitiveCompare(b.id)
                return asc ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        case .size:
            return items.sorted { a, b in
                asc ? a.totalSizeBytes < b.totalSizeBytes : a.totalSizeBytes > b.totalSizeBytes
            }
        case .modified:
            let distant = Date.distantPast
            return items.sorted { a, b in
                let da = a.latestModified ?? distant
                let db = b.latestModified ?? distant
                return asc ? da < db : da > db
            }
        }
    }

    public func refresh() {
        guard !isLoading else { return }
        self.isLoading = true
        self.errorMessage = nil
        Task.detached { [service] in
            do {
                let scanned = try service.scan()
                let total = (try? service.totalSize()) ?? 0
                await MainActor.run {
                    self.artifacts = scanned
                    self.totalSizeBytes = total
                    self.repositoryExists = service.repositoryExists
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.repositoryExists = service.repositoryExists
                    self.isLoading = false
                }
            }
        }
    }

    public func deleteArtifact(_ artifact: MavenArtifact) {
        do {
            try service.deleteArtifact(artifact)
            artifacts.removeAll { $0.id == artifact.id }
            totalSizeBytes -= artifact.totalSizeBytes
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func deleteVersion(_ artifact: MavenArtifact, _ version: MavenArtifactVersion) {
        do {
            try service.deleteVersion(version)
            if let idx = artifacts.firstIndex(where: { $0.id == artifact.id }) {
                var remaining = artifacts[idx].versions.filter { $0.id != version.id }
                if remaining.isEmpty {
                    artifacts.remove(at: idx)
                } else {
                    let newTotal = remaining.reduce(Int64(0)) { $0 + $1.sizeBytes }
                    let newLatest = remaining.compactMap { $0.modifiedAt }.max()
                    artifacts[idx] = MavenArtifact(
                        groupId: artifact.groupId,
                        artifactId: artifact.artifactId,
                        versions: remaining,
                        totalSizeBytes: newTotal,
                        latestModified: newLatest
                    )
                }
                totalSizeBytes -= version.sizeBytes
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// Format a byte count as human-readable text using SI units (MB / GB).
    public static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
