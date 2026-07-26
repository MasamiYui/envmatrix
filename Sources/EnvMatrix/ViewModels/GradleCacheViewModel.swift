import Foundation
import Combine

public enum GradleSortOption: String, CaseIterable, Identifiable, Sendable {
    case sizeDesc
    case sizeAsc
    case mtimeDesc
    case mtimeAsc

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sizeDesc:  return L("gradleCache.sort.sizeDesc")
        case .sizeAsc:   return L("gradleCache.sort.sizeAsc")
        case .mtimeDesc: return L("gradleCache.sort.mtimeDesc")
        case .mtimeAsc:  return L("gradleCache.sort.mtimeAsc")
        }
    }
}

/// Common surface for anything the Gradle cache view sorts by size / mtime.
/// `GradleArtifact` and `GradleWrapperDist` both conform via extensions
/// below — the underlying types already expose these properties.
public protocol GradleSortable {
    var sizeBytes: Int64 { get }
    var modifiedAt: Date? { get }
}

extension GradleArtifact: GradleSortable {}
extension GradleWrapperDist: GradleSortable {}

@MainActor
public final class GradleCacheViewModel: ObservableObject {

    // MARK: - Data / UI state

    @Published public internal(set) var artifacts: [GradleArtifact] = []
    @Published public internal(set) var wrappers: [GradleWrapperDist] = []

    @Published public var artifactSort: GradleSortOption = .sizeDesc
    @Published public var wrapperSort: GradleSortOption = .sizeDesc

    @Published public var artifactSearch: String = ""
    @Published public var wrapperSearch: String = ""

    @Published public var selectedArtifactIDs: Set<String> = []
    @Published public var selectedWrapperIDs: Set<String> = []

    @Published public private(set) var isScanning: Bool = false
    @Published public var errorMessage: String?

    public init() {}

    // MARK: - Filtering & sorting

    public var visibleArtifacts: [GradleArtifact] {
        let q = artifactSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var arr = artifacts
        if !q.isEmpty {
            arr = arr.filter {
                "\($0.group):\($0.artifact)".lowercased().contains(q)
                    || $0.version.lowercased().contains(q)
            }
        }
        return Self.sort(arr, by: artifactSort)
    }

    public var visibleWrappers: [GradleWrapperDist] {
        let q = wrapperSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var arr = wrappers
        if !q.isEmpty {
            arr = arr.filter { $0.versionLabel.lowercased().contains(q) }
        }
        return Self.sort(arr, by: wrapperSort)
    }

    // MARK: - Totals

    public var artifactsTotalBytes: Int64 { artifacts.reduce(0) { $0 + $1.sizeBytes } }
    public var wrappersTotalBytes: Int64 { wrappers.reduce(0) { $0 + $1.sizeBytes } }
    public var grandTotalBytes: Int64 { artifactsTotalBytes + wrappersTotalBytes }

    // MARK: - Scan

    public func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        // Construct a fresh FileManager instance inside the detached task to
        // avoid capturing the non-Sendable `FileManager.default` singleton.
        let scanned = await Task.detached(priority: .userInitiated) {
            () -> ([GradleArtifact], [GradleWrapperDist]) in
            let fm = FileManager()
            let arts = GradleCacheService.scanArtifacts(fm: fm)
            let wraps = GradleCacheService.scanWrapperDists(fm: fm)
            return (arts, wraps)
        }.value
        self.artifacts = scanned.0
        self.wrappers = scanned.1
        self.isScanning = false
    }

    // MARK: - Deletion

    public func deleteArtifacts(_ ids: Set<String>) async {
        await deleteBatch(ids: ids, kind: .artifact)
    }

    public func deleteWrappers(_ ids: Set<String>) async {
        await deleteBatch(ids: ids, kind: .wrapper)
    }

    public func deleteAllSelected() async {
        await deleteArtifacts(selectedArtifactIDs)
        await deleteWrappers(selectedWrapperIDs)
    }

    // MARK: - Private

    private enum Kind { case artifact, wrapper }

    private func deleteBatch(ids: Set<String>, kind: Kind) async {
        guard !ids.isEmpty else { return }
        let urls: [(String, URL)]
        switch kind {
        case .artifact:
            urls = artifacts.filter { ids.contains($0.id) }.map { ($0.id, $0.url) }
        case .wrapper:
            urls = wrappers.filter { ids.contains($0.id) }.map { ($0.id, $0.url) }
        }
        guard !urls.isEmpty else { return }

        var deleted: Set<String> = []
        var errors: [String] = []
        await withTaskGroup(of: (String, String?).self) { group in
            for (id, url) in urls {
                group.addTask(priority: .userInitiated) {
                    await Task.detached { () -> (String, String?) in
                        do {
                            try GradleCacheService.moveToTrash(url)
                            return (id, nil)
                        } catch {
                            return (id, error.localizedDescription)
                        }
                    }.value
                }
            }
            for await (id, err) in group {
                if let err { errors.append(err) } else { deleted.insert(id) }
            }
        }

        switch kind {
        case .artifact:
            artifacts.removeAll { deleted.contains($0.id) }
            selectedArtifactIDs.subtract(deleted)
        case .wrapper:
            wrappers.removeAll { deleted.contains($0.id) }
            selectedWrapperIDs.subtract(deleted)
        }

        if !errors.isEmpty {
            let joined = errors.joined(separator: "\n")
            errorMessage = errorMessage.map { "\($0)\n\(joined)" } ?? joined
        }
    }

    /// Pure helper — kept `static` so it is trivially testable and does not
    /// close over `self`. `nil` mtime sorts as `Date.distantPast`.
    static func sort<T: GradleSortable>(
        _ arr: [T],
        by opt: GradleSortOption
    ) -> [T] {
        switch opt {
        case .sizeDesc:
            return arr.sorted { $0.sizeBytes > $1.sizeBytes }
        case .sizeAsc:
            return arr.sorted { $0.sizeBytes < $1.sizeBytes }
        case .mtimeDesc:
            return arr.sorted { lhs, rhs in
                let l = lhs.modifiedAt ?? .distantPast
                let r = rhs.modifiedAt ?? .distantPast
                return l > r
            }
        case .mtimeAsc:
            return arr.sorted { lhs, rhs in
                let l = lhs.modifiedAt ?? .distantPast
                let r = rhs.modifiedAt ?? .distantPast
                return l < r
            }
        }
    }
}
