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

@MainActor
public final class ProjectEnvViewModel: ObservableObject {

    // MARK: - Persisted roots

    /// UserDefaults key for the JSON-serialised list of user-configured roots.
    /// We store bookmark-less paths for simplicity — this app is not sandboxed
    /// so plain paths are sufficient and much easier to reason about than
    /// security-scoped bookmarks.
    private static let rootsStorageKey = "projenv.roots.v1"

    @Published public var roots: [URL] {
        didSet { persistRoots() }
    }

    // MARK: - Data / UI state

    @Published public private(set) var environments: [ProjectEnvironment] = []
    @Published public private(set) var totalBytes: Int64 = 0
    @Published public private(set) var scanDuration: TimeInterval = 0

    @Published public var kindFilter: ProjectEnvKindFilter = .all
    @Published public var searchText: String = ""
    @Published public var minSizeMB: Double = 0     // slider — 0 disables filter
    @Published public var selectedEnvID: String?

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
    }

    // MARK: - Derived

    /// The filtered list actually rendered in the middle column.
    public var visibleEnvironments: [ProjectEnvironment] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let minBytes = Int64(minSizeMB * 1024 * 1024)
        return environments.filter { env in
            guard kindFilter.matches(env.kind) else { return false }
            if minBytes > 0, (env.sizeBytes ?? 0) < minBytes { return false }
            if q.isEmpty { return true }
            if env.projectRoot.path.lowercased().contains(q) { return true }
            if env.url.path.lowercased().contains(q) { return true }
            return false
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
            if selectedEnvID == env.id { selectedEnvID = environments.first?.id }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
