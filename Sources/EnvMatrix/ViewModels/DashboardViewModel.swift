import Foundation
import SwiftUI

@MainActor
public final class DashboardViewModel: ObservableObject {
    public struct RuntimeSnapshot: Identifiable {
        public let kind: RuntimeKind
        public let activeVersion: String?
        public let isSystemDefault: Bool
        public var id: String { kind.rawValue }
    }

    public struct PackageSnapshot: Identifiable {
        public enum Kind: String {
            case brew, maven, go, node
        }
        public let kind: Kind
        public let cacheBytes: Int64
        public let itemCount: Int?
        public let needsAttention: Bool
        public var id: String { kind.rawValue }
    }

    @Published public var runtimes: [RuntimeSnapshot] = []
    @Published public var skillsCount: Int = 0
    @Published public var mcpCount: Int = 0
    @Published public var storageBytes: Int64 = 0
    @Published public var isLoading: Bool = false
    @Published public var packages: [PackageSnapshot] = []

    /// Threshold in bytes above which a package cache is considered
    /// "in need of cleaning". 5 GB — chosen so GOMODCACHE / .m2 caches
    /// on a typical developer machine only trigger after real accumulation.
    public static let cleanupThresholdBytes: Int64 = 5 * 1024 * 1024 * 1024

    private let runtimeService: RuntimeService
    private let skillsService: SkillsService
    private let mcpService: MCPService
    private let versionsDir: URL
    private let shimsDir: URL
    private let fileManager: FileManager

    // Guards: prevent overlapping refresh() calls (e.g. rapid navigation) and
    // avoid re-running expensive work when the view is re-entered.
    private var hasLoadedOnce = false
    private var isRefreshing = false

    public init(
        runtimeService: RuntimeService = DefaultRuntimeService(),
        skillsService: SkillsService = DefaultSkillsService(),
        mcpService: MCPService = DefaultMCPService(),
        versionsDir: URL = FileSystem.versionsDir,
        shimsDir: URL = FileSystem.envmatrixRoot.appendingPathComponent("shims", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.runtimeService = runtimeService
        self.skillsService = skillsService
        self.mcpService = mcpService
        self.versionsDir = versionsDir
        self.shimsDir = shimsDir
        self.fileManager = fileManager
        self.runtimes = RuntimeKind.allCases.map {
            RuntimeSnapshot(kind: $0, activeVersion: nil, isSystemDefault: false)
        }
    }

    /// Called from `.task` every time the view appears. Idempotent: if we've
    /// already loaded once (and are not being asked to force a fresh scan),
    /// this is a no-op so navigating away and back is instant.
    public func refresh() async {
        if hasLoadedOnce { return }
        await performRefresh()
    }

    /// Explicit user-triggered refresh: drops the runtime detector's caches
    /// so a stale-but-fast cached view is replaced with a fresh scan.
    public func hardRefresh() async {
        runtimeService.invalidateSystemCaches()
        hasLoadedOnce = false
        await performRefresh()
    }

    private func performRefresh() async {
        // Reentry guard so rapid navigation / repeated .task fires can't
        // stack up parallel refreshes (which would fork subprocesses again).
        if isRefreshing { return }
        isRefreshing = true
        isLoading = true
        defer {
            isRefreshing = false
            isLoading = false
        }

        let runtimeSvc = runtimeService
        let shims = shimsDir
        let skillsSvc = skillsService
        let mcpSvc = mcpService
        let dir = versionsDir

        // --- Phase 1 -----------------------------------------------------
        // Fast payload: runtime snapshots + skills/mcp counts.
        //
        // IMPORTANT: we deliberately do NOT use `withTaskGroup` here. Empirical
        // logs (see git history for debug-dashboard-stale-and-slow) show that
        // when a task-group's child tasks capture non-Sendable references
        // (RuntimeService is a class), the Swift concurrency runtime under
        // Swift 5 mode on macOS 26 can silently deadlock — no error, no log,
        // phase1 never completes, dashboard stays at zero forever. A single
        // detached task with a plain synchronous for-loop is boring, portable,
        // and works.
        let phase1 = await Task.detached(priority: .userInitiated) {
            () -> (snapshots: [RuntimeSnapshot], skills: Int, mcp: Int) in
            let fm = FileManager.default
            var snapshots: [RuntimeSnapshot] = []
            snapshots.reserveCapacity(RuntimeKind.allCases.count)
            for kind in RuntimeKind.allCases {
                let version = runtimeSvc.currentActive(kind: kind)
                let shim = shims.appendingPathComponent(kind.binaryName)
                let attrs = try? fm.attributesOfItem(atPath: shim.path)
                let shimExists = (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink
                snapshots.append(RuntimeSnapshot(
                    kind: kind,
                    activeVersion: version,
                    isSystemDefault: version != nil && !shimExists
                ))
            }
            let skills = (try? skillsSvc.list().count) ?? 0
            let mcp = (try? mcpSvc.list().count) ?? 0
            return (snapshots, skills, mcp)
        }.value

        self.runtimes = phase1.snapshots
        self.skillsCount = phase1.skills
        self.mcpCount = phase1.mcp
        self.hasLoadedOnce = true

        // --- Phase 2 -----------------------------------------------------
        // Folder size is the slowest thing we do (recursive enumeration of
        // ~/.envmatrix/versions). Don't block phase 1 UI on it — kick it
        // off, let the MainActor return, and update storageBytes when done.
        let bytes = await Task.detached(priority: .utility) {
            FolderSizeCalculator.compute(at: dir)
        }.value
        self.storageBytes = bytes

        // --- Phase 3 -----------------------------------------------------
        // Package caches (Homebrew, Maven, Go, npm). Each of these can be
        // multi-GB on a developer machine, and they change slowly, so we
        // compute in the background with utility QoS.
        let threshold = Self.cleanupThresholdBytes
        let pkgs = await Task.detached(priority: .utility) {
            () -> [PackageSnapshot] in
            let home = URL(fileURLWithPath: NSHomeDirectory())
            let brew = FolderSizeCalculator.compute(
                at: home.appendingPathComponent("Library/Caches/Homebrew", isDirectory: true))
            let maven = FolderSizeCalculator.compute(
                at: home.appendingPathComponent(".m2/repository", isDirectory: true))
            let goMod = FolderSizeCalculator.compute(
                at: home.appendingPathComponent("go/pkg/mod", isDirectory: true))
            let npm = FolderSizeCalculator.compute(
                at: home.appendingPathComponent(".npm/_cacache", isDirectory: true))
            return [
                PackageSnapshot(kind: .brew, cacheBytes: brew, itemCount: nil,
                                needsAttention: brew > threshold),
                PackageSnapshot(kind: .maven, cacheBytes: maven, itemCount: nil,
                                needsAttention: maven > threshold),
                PackageSnapshot(kind: .go, cacheBytes: goMod, itemCount: nil,
                                needsAttention: goMod > threshold),
                PackageSnapshot(kind: .node, cacheBytes: npm, itemCount: nil,
                                needsAttention: npm > threshold)
            ]
        }.value
        self.packages = pkgs
    }

    public static func folderSize(at url: URL) async -> Int64 {
        await Task.detached(priority: .utility) { () -> Int64 in
            FolderSizeCalculator.compute(at: url)
        }.value
    }
}

enum FolderSizeCalculator {
    static func compute(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true, let size = values?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
