import Foundation

/// Discovers `Python venv` and `node_modules` directories under a set of
/// user-configured project roots.
///
/// Design notes:
/// - **Bounded depth BFS** (default 6). Blindly walking `~` would traverse
///   every hidden cache and `Library` folder on the machine.
/// - **Prune aggressively**: never descend into folders whose *name* is known
///   to be either huge, opaque, or already accounted for
///   (`node_modules`, `.git`, `Library`, `.Trash`, `Pods`, `.gradle`, …).
///   Once we find `node_modules` we still walk it to compute its size, but we
///   don't look inside for further environments.
/// - **Parallel**: siblings are walked concurrently via `withTaskGroup`, capped
///   at a small degree of parallelism to stay friendly to spinning disks and
///   the SSD's IOPS budget.
/// - **Robust to permission failures**: every enumeration is wrapped so a
///   single unreadable directory (e.g. `~/Library/Application Support`) does
///   not abort the whole scan.
public struct ProjectEnvScanner: Sendable {

    // MARK: - Configuration

    public struct Options: Sendable {
        public var maxDepth: Int
        public var maxParallel: Int
        public var skipDirNames: Set<String>

        public static let `default` = Options(
            maxDepth: 6,
            maxParallel: 6,
            skipDirNames: [
                // VCS / editor scaffolding
                ".git", ".hg", ".svn", ".idea", ".vscode",
                // macOS system / cache dirs
                "Library", ".Trash", ".cache", ".DS_Store", "Applications",
                // Language-specific opaque caches
                "Pods", ".gradle", ".m2", ".cargo", "target",
                "build", "DerivedData", "dist", "out", "coverage",
                "__pycache__", ".mypy_cache", ".pytest_cache",
                ".tox", ".ruff_cache", ".next", ".nuxt", ".turbo",
                ".yarn", ".pnpm-store"
            ]
        )

        public init(maxDepth: Int, maxParallel: Int, skipDirNames: Set<String>) {
            self.maxDepth = maxDepth
            self.maxParallel = maxParallel
            self.skipDirNames = skipDirNames
        }
    }

    // MARK: - Default roots

    /// A curated list of well-known project root candidates in a user's
    /// `$HOME`. We only return the ones that actually exist so first-run
    /// experience shows something useful without prompting.
    public static func defaultRootsIfPresent() -> [URL] {
        let home = FileSystem.homeURL
        let candidates = [
            "Projects", "Documents", "Code", "Developer",
            "OpenSoureProjects", "OpenSourceProjects", "workspace", "work",
            "repos", "src"
        ]
        return candidates
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { url in
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                return exists && isDir.boolValue
            }
    }

    // MARK: - API

    public var options: Options

    public init(options: Options = .default) {
        self.options = options
    }

    /// Walk each root and return every environment we discover.
    public func scan(roots: [URL]) async -> ProjectEnvInventory {
        let start = Date()
        let fm = FileManager.default
        let usable = roots.filter { url in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
        var found: [ProjectEnvironment] = []

        // Sequential over roots keeps memory bounded — inside each root we go
        // parallel.
        for root in usable {
            let subset = await walk(root: root)
            found.append(contentsOf: subset)
        }

        // Dedup by absolute path (defensive: symlinks or duplicate roots).
        var seen = Set<String>()
        var deduped: [ProjectEnvironment] = []
        for env in found where seen.insert(env.url.path).inserted {
            deduped.append(env)
        }

        let total = deduped.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
        return ProjectEnvInventory(
            environments: deduped.sorted(by: { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }),
            rootsScanned: usable,
            totalBytes: total,
            scanDuration: Date().timeIntervalSince(start)
        )
    }

    // MARK: - Traversal

    private func walk(root: URL) async -> [ProjectEnvironment] {
        // BFS with (URL, depth). We use an actor-less accumulator because
        // we only append from the enclosing task after each level completes.
        var queue: [(URL, Int)] = [(root, 0)]
        var results: [ProjectEnvironment] = []
        let fm = FileManager.default

        while !queue.isEmpty {
            // Grab up to maxParallel entries this batch.
            let batchSize = min(options.maxParallel, queue.count)
            let batch = Array(queue.prefix(batchSize))
            queue.removeFirst(batchSize)

            let output: [(matches: [ProjectEnvironment], children: [(URL, Int)])] =
                await withTaskGroup(of: (matches: [ProjectEnvironment], children: [(URL, Int)]).self) { group in
                    for (dir, depth) in batch {
                        group.addTask { [options] in
                            await Self.inspect(
                                dir: dir,
                                depth: depth,
                                options: options,
                                fm: fm
                            )
                        }
                    }
                    var acc: [(matches: [ProjectEnvironment], children: [(URL, Int)])] = []
                    for await item in group { acc.append(item) }
                    return acc
                }

            for item in output {
                results.append(contentsOf: item.matches)
                queue.append(contentsOf: item.children)
            }
        }

        return results
    }

    /// Inspect a single directory. Returns any environments discovered *at*
    /// this directory and the list of children to enqueue for further walking.
    private static func inspect(
        dir: URL,
        depth: Int,
        options: Options,
        fm: FileManager
    ) async -> (matches: [ProjectEnvironment], children: [(URL, Int)]) {
        var matches: [ProjectEnvironment] = []
        var children: [(URL, Int)] = []

        // Skip explicit blocked names — do this first so we never even stat
        // the contents of well-known heavy directories.
        if options.skipDirNames.contains(dir.lastPathComponent) {
            return ([], [])
        }

        // 1. Is *this* directory itself a venv or a node_modules? We answer
        //    that by looking at its sentinel files instead of relying on the
        //    directory name so we do not miss uncommon naming conventions
        //    (e.g. `env`, `.venv`, `venv312`).
        if let asVenv = detectVenv(at: dir, fm: fm) {
            matches.append(asVenv)
            // A venv's `lib/python*/site-packages` is huge but has no further
            // environments inside it. Don't recurse.
            return (matches, [])
        }
        if let asNodeModules = detectNodeModules(at: dir, fm: fm) {
            matches.append(asNodeModules)
            // Same rationale — do not recurse into node_modules itself.
            return (matches, [])
        }

        // 2. Otherwise, enumerate children and queue directories for the
        //    next BFS level.
        guard depth < options.maxDepth else { return (matches, []) }

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles.union(.skipsPackageDescendants)]
            )
        } catch {
            // Unreadable directory — silently skip. This is common inside
            // `~/Library` and sandbox-protected folders.
            return (matches, [])
        }

        for child in contents {
            // Fast-path skip on name.
            if options.skipDirNames.contains(child.lastPathComponent) { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else { continue }

            // Avoid recursing through symlinks — cycles will explode the walk.
            let resolved = try? child.resourceValues(forKeys: [.isSymbolicLinkKey])
            if resolved?.isSymbolicLink == true { continue }

            children.append((child, depth + 1))
        }

        return (matches, children)
    }

    // MARK: - Detection helpers

    /// A Python venv is identified by the presence of `pyvenv.cfg` at its root.
    private static func detectVenv(at dir: URL, fm: FileManager) -> ProjectEnvironment? {
        let cfg = dir.appendingPathComponent("pyvenv.cfg")
        guard fm.fileExists(atPath: cfg.path) else { return nil }

        let python = parseVenvPythonVersion(at: cfg)
        let size = directorySize(at: dir, fm: fm)
        let mtime = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        return ProjectEnvironment(
            kind: .venv,
            url: dir,
            projectRoot: dir.deletingLastPathComponent(),
            sizeBytes: size,
            pythonVersion: python,
            packageManager: nil,
            modifiedAt: mtime
        )
    }

    /// A `node_modules` is identified structurally: name matches and its
    /// sibling `package.json` exists. This filters out random folders that
    /// happen to be named node_modules but are unrelated (rare but real).
    private static func detectNodeModules(at dir: URL, fm: FileManager) -> ProjectEnvironment? {
        guard dir.lastPathComponent == "node_modules" else { return nil }
        let parent = dir.deletingLastPathComponent()
        let pkgJSON = parent.appendingPathComponent("package.json")
        guard fm.fileExists(atPath: pkgJSON.path) else { return nil }

        let pm = detectPackageManager(projectRoot: parent, fm: fm)
        let size = directorySize(at: dir, fm: fm)
        let mtime = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        return ProjectEnvironment(
            kind: .nodeModules,
            url: dir,
            projectRoot: parent,
            sizeBytes: size,
            pythonVersion: nil,
            packageManager: pm,
            modifiedAt: mtime
        )
    }

    /// Infer the JS package manager by looking for lockfiles in the project
    /// root. Preference order matches the ecosystem's own conventions.
    private static func detectPackageManager(projectRoot: URL, fm: FileManager) -> JSPackageManager {
        let order: [JSPackageManager] = [.pnpm, .yarn, .bun, .npm]
        for pm in order {
            if let name = pm.lockfileName {
                let f = projectRoot.appendingPathComponent(name)
                if fm.fileExists(atPath: f.path) { return pm }
            }
        }
        return .unknown
    }

    /// Read `pyvenv.cfg` to extract `version_info` or `version`.
    private static func parseVenvPythonVersion(at cfgURL: URL) -> String? {
        guard let text = try? String(contentsOf: cfgURL, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            if key == "version_info" || key == "version" {
                return String(parts[1])
            }
        }
        return nil
    }

    /// Compute directory size by walking every regular file inside. This is
    /// synchronous but bounded in scope (we only ever run it on a matched env,
    /// which is a leaf in our BFS). For truly enormous `node_modules`
    /// (>500k files) this may take a few hundred ms; we accept that trade-off
    /// to give users an accurate "reclaimable space" figure.
    private static func directorySize(at url: URL, fm: FileManager) -> Int64? {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true /* keep going */ }
        ) else { return nil }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            guard values?.isRegularFile == true else { continue }
            if let s = values?.totalFileAllocatedSize {
                total += Int64(s)
            } else if let s = values?.fileAllocatedSize {
                total += Int64(s)
            }
        }
        return total
    }
}
