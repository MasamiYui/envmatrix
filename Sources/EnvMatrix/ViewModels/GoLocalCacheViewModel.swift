import Foundation

public enum GoModuleSortMode: String, CaseIterable, Identifiable {
    case name
    case size
    case modified
    public var id: String { rawValue }
}

@MainActor
public final class GoLocalCacheViewModel: ObservableObject {
    @Published public var artifacts: [GoModuleArtifact] = []
    @Published public var totalSizeBytes: Int64 = 0
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var searchText: String = ""
    @Published public var sortMode: GoModuleSortMode = .name
    @Published public var sortAscending: Bool = true
    @Published public var cacheExists: Bool = false
    @Published public var cachePath: String = ""

    private let service: GoLocalCacheService

    public init(service: GoLocalCacheService = DefaultGoLocalCacheService()) {
        self.service = service
        self.cachePath = service.cacheURL.path
        self.cacheExists = service.cacheExists
    }

    public var filteredArtifacts: [GoModuleArtifact] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [GoModuleArtifact]
        if q.isEmpty {
            filtered = artifacts
        } else {
            filtered = artifacts.filter { art in
                art.modulePath.lowercased().contains(q)
                    || art.versions.contains { $0.version.lowercased().contains(q) }
            }
        }
        return sorted(filtered)
    }

    private func sorted(_ items: [GoModuleArtifact]) -> [GoModuleArtifact] {
        let asc = sortAscending
        switch sortMode {
        case .name:
            return items.sorted { a, b in
                let cmp = a.modulePath.localizedCaseInsensitiveCompare(b.modulePath)
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
                    self.cacheExists = service.cacheExists
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.cacheExists = service.cacheExists
                    self.isLoading = false
                }
            }
        }
    }

    public func deleteModule(_ artifact: GoModuleArtifact) {
        do {
            try service.deleteModule(artifact)
            artifacts.removeAll { $0.id == artifact.id }
            totalSizeBytes -= artifact.totalSizeBytes
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func deleteVersion(_ artifact: GoModuleArtifact, _ version: GoModuleVersion) {
        do {
            try service.deleteVersion(version)
            if let idx = artifacts.firstIndex(where: { $0.id == artifact.id }) {
                let remaining = artifacts[idx].versions.filter { $0.id != version.id }
                if remaining.isEmpty {
                    artifacts.remove(at: idx)
                } else {
                    let newTotal = remaining.reduce(Int64(0)) { $0 + $1.sizeBytes }
                    let newLatest = remaining.compactMap { $0.modifiedAt }.max()
                    artifacts[idx] = GoModuleArtifact(
                        modulePath: artifact.modulePath,
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

    public static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
