import Foundation
import SwiftUI

/// The kind filter shown in the toolbar segmented control.
public enum ProjectEnvKindFilter: String, CaseIterable, Identifiable {
    case all, venv, nodeModules
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return L("projenv.filter.all")
        case .venv: return "Python venv"
        case .nodeModules: return "node_modules"
        }
    }

    public func matches(_ kind: ProjectEnvKind) -> Bool {
        switch self {
        case .all: return true
        case .venv: return kind == .venv
        case .nodeModules: return kind == .nodeModules
        }
    }
}

/// Sort order applied to the visible list.
public enum ProjectEnvSortOption: String, CaseIterable, Identifiable {
    case sizeDesc
    case sizeAsc
    case mtimeAsc
    case mtimeDesc

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sizeDesc: return L("projenv.sort.sizeDesc")
        case .sizeAsc:  return L("projenv.sort.sizeAsc")
        case .mtimeAsc: return L("projenv.sort.mtimeAsc")
        case .mtimeDesc:return L("projenv.sort.mtimeDesc")
        }
    }
}

/// Coarse liveness bucket derived from the environment's mtime — used to
/// highlight likely-abandoned caches in the UI.
public enum ProjectEnvHealth: String {
    case active
    case idle
    case abandoned

    public var label: String {
        switch self {
        case .active:    return L("projenv.health.active")
        case .idle:      return L("projenv.health.idle")
        case .abandoned: return L("projenv.health.abandoned")
        }
    }

    public var hex: String {
        switch self {
        case .active:    return "#3DBE6A"
        case .idle:      return "#F4B400"
        case .abandoned: return "#8E8E93"
        }
    }
}

@MainActor
public final class ProjectEnvViewModel: ObservableObject {

    // MARK: - Persisted roots

    /// UserDefaults key for the JSON-serialised list of user-configured roots.
    /// We store bookmark-less paths for simplicity — this app is not sandboxed
    /// so plain paths are sufficient and much easier to reason about than
    /// security-scoped bookmarks.
    private static let rootsStorageKey = "projenv.roots.v1"
    private static let includeDerivedDataKey = "projenv.includeXcodeDerivedData.v1"

    @Published public var roots: [URL] {
        didSet { persistRoots() }
    }

    // MARK: - Data / UI state

    @Published public internal(set) var environments: [ProjectEnvironment] = []
    @Published public private(set) var totalBytes: Int64 = 0
    @Published public private(set) var scanDuration: TimeInterval = 0

    @Published public var kindFilter: ProjectEnvKindFilter = .all
    @Published public var searchText: String = ""
    @Published public var minSizeMB: Double = 0     // slider — 0 disables filter
    @Published public var sortOption: ProjectEnvSortOption = .sizeDesc
    @Published public var selectedEnvID: String?
    @Published public var selectedEnvIDs: Set<String> = []

    @Published public var includeXcodeDerivedData: Bool {
        didSet {
            UserDefaults.standard.set(includeXcodeDerivedData, forKey: Self.includeDerivedDataKey)
        }
    }

    @Published public private(set) var isScanning: Bool = false
    @Published public var errorMessage: String?

    /// Live log lines while a reinstall or delete is in flight.
    @Published public private(set) var opLog: [String] = []
    @Published public private(set) var runningOpID: String?

    private let scanner: ProjectEnvScanner
    private let operations: ProjectEnvOperations
    private var hasScannedOnce = false

    // MARK: - Init

    public init(
        scanner: ProjectEnvScanner = ProjectEnvScanner(),
        operations: ProjectEnvOperations = ProjectEnvOperations()
    ) {
        self.scanner = scanner
        self.operations = operations
        self.roots = Self.loadRoots() ?? ProjectEnvScanner.defaultRootsIfPresent()
        self.includeXcodeDerivedData = UserDefaults.standard.bool(forKey: Self.includeDerivedDataKey)
    }

    // MARK: - Derived

    /// The filtered + sorted list actually rendered in the middle column.
    public var visibleEnvironments: [ProjectEnvironment] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let minBytes = Int64(minSizeMB * 1024 * 1024)
        let filtered = environments.filter { env in
            guard kindFilter.matches(env.kind) else { return false }
            if minBytes > 0, (env.sizeBytes ?? 0) < minBytes { return false }
            if q.isEmpty { return true }
            if env.projectRoot.path.lowercased().contains(q) { return true }
            if env.url.path.lowercased().contains(q) { return true }
            return false
        }
        return Self.sort(filtered, by: sortOption)
    }

    /// Pure helper — kept `static` so it is trivially testable and does not
    /// close over `self`.
    static func sort(
        _ envs: [ProjectEnvironment],
        by option: ProjectEnvSortOption
    ) -> [ProjectEnvironment] {
        switch option {
        case .sizeDesc:
            return envs.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
        case .sizeAsc:
            return envs.sorted { ($0.sizeBytes ?? 0) < ($1.sizeBytes ?? 0) }
        case .mtimeAsc:
            // Oldest (or missing) first.
            return envs.sorted { lhs, rhs in
                let l = lhs.modifiedAt ?? .distantPast
                let r = rhs.modifiedAt ?? .distantPast
                return l < r
            }
        case .mtimeDesc:
            // Newest first; missing mtimes drop to the bottom.
            return envs.sorted { lhs, rhs in
                let l = lhs.modifiedAt ?? .distantPast
                let r = rhs.modifiedAt ?? .distantPast
                return l > r
            }
        }
    }

    public var selectedEnv: ProjectEnvironment? {
        guard let id = selectedEnvID else { return nil }
        return environments.first(where: { $0.id == id })
    }

    /// Reclaimable bytes across the currently visible list (respects filters).
    public var visibleTotalBytes: Int64 {
        visibleEnvironments.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }

    /// Environments the ViewModel considers likely-abandoned. Callers use this
    /// for the "clean everything" bulk action.
    public var abandonedEnvironments: [ProjectEnvironment] {
        environments.filter { Self.health(for: $0) == .abandoned }
    }

    public var abandonedTotalBytes: Int64 {
        abandonedEnvironments.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }

    // MARK: - Health

    /// Bucket an environment into active / idle / abandoned based on its
    /// modification date. `nil` mtime is treated as abandoned so we default
    /// to a conservative "flag it" state rather than silently ignoring it.
    public static func health(
        for env: ProjectEnvironment,
        now: Date = Date()
    ) -> ProjectEnvHealth {
        guard let mtime = env.modifiedAt else { return .abandoned }
        let days = now.timeIntervalSince(mtime) / 86_400
        if days <= 30 { return .active }
        if days <= 180 { return .idle }
        return .abandoned
    }

    public func health(for env: ProjectEnvironment) -> ProjectEnvHealth {
        Self.health(for: env)
    }

    // MARK: - Lifecycle

    public func refreshIfNeeded() async {
        guard !hasScannedOnce else { return }
        await rescan()
    }

    /// Kick off a full scan of the current roots. Safe to call while another
    /// scan is in flight — we bail out if `isScanning` is already true.
    public func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        defer { isScanning = false; hasScannedOnce = true }

        let rootsSnapshot = roots
        let scannerCopy = scanner
        let inventory = await Task.detached(priority: .userInitiated) {
            await scannerCopy.scan(roots: rootsSnapshot)
        }.value

        self.environments = inventory.environments
        self.totalBytes = inventory.totalBytes
        self.scanDuration = inventory.scanDuration
        // Auto-select the largest match if nothing is selected yet.
        if selectedEnvID == nil {
            selectedEnvID = inventory.environments.first?.id
        }

        // Optional: pick up Xcode DerivedData in a detached background task.
        // We construct a fresh FileManager instance inside the task to avoid
        // capturing the non-Sendable `FileManager.default` singleton.
        if includeXcodeDerivedData {
            let extra = await Task.detached(priority: .userInitiated) { () -> [ProjectEnvironment] in
                let fm = FileManager()
                return ProjectEnvScanner.detectXcodeDerivedData(fm: fm)
            }.value
            guard !extra.isEmpty else { return }
            let existingIDs = Set(self.environments.map(\.id))
            let merged = extra.filter { !existingIDs.contains($0.id) }
            self.environments.append(contentsOf: merged)
            self.totalBytes = self.environments.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
        }
    }

    // MARK: - Roots management

    public func addRoot(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard !roots.contains(normalized) else { return }
        roots.append(normalized)
    }

    public func removeRoot(_ url: URL) {
        roots.removeAll(where: { $0 == url })
    }

    // MARK: - Operations

    /// Move `env` to the Trash and drop it from our in-memory list.
    public func delete(_ env: ProjectEnvironment) {
        do {
            try operations.moveToTrash(env)
            environments.removeAll(where: { $0.id == env.id })
            totalBytes = environments.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
            selectedEnvIDs.remove(env.id)
            if selectedEnvID == env.id { selectedEnvID = environments.first?.id }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Move many environments to the Trash concurrently. Each failure is
    /// merged into `errorMessage` — we intentionally continue on failure so
    /// one broken row does not block the rest of the batch.
    public func deleteMany(_ ids: Set<String>) async {
        guard !ids.isEmpty else { return }
        // Snapshot the environments we actually want to delete.
        let targets = environments.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        let ops = operations
        let results: [(String, String?)] = await withTaskGroup(
            of: (String, String?).self
        ) { group in
            for env in targets {
                group.addTask {
                    // Sync IO — hop off the main actor.
                    await Task.detached(priority: .userInitiated) { () -> (String, String?) in
                        do {
                            try ops.moveToTrash(env)
                            return (env.id, nil)
                        } catch {
                            let msg = (error as? LocalizedError)?.errorDescription
                                ?? error.localizedDescription
                            return (env.id, msg)
                        }
                    }.value
                }
            }
            var acc: [(String, String?)] = []
            for await result in group { acc.append(result) }
            return acc
        }

        let deletedIDs: Set<String> = Set(
            results.compactMap { $0.1 == nil ? $0.0 : nil }
        )
        let failures: [String] = results.compactMap { $0.1 }

        if !deletedIDs.isEmpty {
            environments.removeAll(where: { deletedIDs.contains($0.id) })
            totalBytes = environments.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
        }

        selectedEnvIDs.subtract(deletedIDs)
        if let sid = selectedEnvID, deletedIDs.contains(sid) {
            selectedEnvID = environments.first?.id
        }

        if !failures.isEmpty {
            let joined = failures.joined(separator: "\n")
            errorMessage = errorMessage.map { "\($0)\n\(joined)" } ?? joined
        }
    }

    /// Bulk-delete every environment classified as `.abandoned`.
    public func deleteAllAbandoned() async {
        await deleteMany(Set(abandonedEnvironments.map(\.id)))
    }

    /// Delete then reinstall a node_modules folder. Emits log lines to
    /// `opLog`. `runningOpID` guards the button from double-clicks.
    public func reinstall(_ env: ProjectEnvironment) async {
        guard runningOpID == nil else { return }
        runningOpID = env.id
        opLog.removeAll()
        errorMessage = nil
        defer { runningOpID = nil }

        do {
            let result = try await operations.reinstallNodeModules(env) { [weak self] chunk in
                Task { @MainActor [weak self] in
                    self?.appendLog(chunk)
                }
            }
            appendLog("\n[envmatrix] process exited with code \(result.exitCode)\n")
            // Trigger a rescan to reflect the new folder + its size.
            await rescan()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            appendLog("\n[envmatrix] error: \(errorMessage ?? "")\n")
        }
    }

    public func reveal(_ env: ProjectEnvironment) {
        operations.revealInFinder(env)
    }

    public func revealProject(_ env: ProjectEnvironment) {
        operations.revealProjectInFinder(env)
    }

    public func openInTerminal(_ env: ProjectEnvironment) {
        do {
            try operations.openInTerminal(env)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Log accumulator

    private func appendLog(_ text: String) {
        // Split on newlines so we render nice per-line entries, but never grow
        // the buffer beyond a sane bound (react to very chatty installs).
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            opLog.append(String(line))
        }
        if opLog.count > 2000 {
            opLog.removeFirst(opLog.count - 2000)
        }
    }

    // MARK: - Persistence

    private func persistRoots() {
        let paths = roots.map(\.path)
        UserDefaults.standard.set(paths, forKey: Self.rootsStorageKey)
    }

    private static func loadRoots() -> [URL]? {
        guard let paths = UserDefaults.standard.stringArray(forKey: rootsStorageKey), !paths.isEmpty else {
            return nil
        }
        return paths.map { URL(fileURLWithPath: $0) }
    }
}
