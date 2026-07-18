import Foundation

public enum RuntimeServiceError: Error, LocalizedError {
    case network(String)
    case decoding(String)
    case notFound
    case unsupportedArch
    case notInstalled(String)
    case systemManaged(String)
    case permissionDenied(path: String, suggestion: String)

    public var errorDescription: String? {
        switch self {
        case .network(let msg): return "Network error: \(msg)"
        case .decoding(let msg): return "Decoding error: \(msg)"
        case .notFound: return "Not found"
        case .unsupportedArch: return "Unsupported architecture"
        case .notInstalled(let name): return "Not installed: \(name)"
        case .systemManaged(let name):
            return "Cannot uninstall system-managed runtime: \(name). "
                 + "Remove it via the installer that placed it (brew, pkg, asdf, ...)"
        case .permissionDenied(let path, let suggestion):
            return "Permission denied removing \(path). Suggested command:\n\(suggestion)"
        }
    }
}

public protocol VersionProvider {
    var kind: RuntimeKind { get }
    func listAvailable() async throws -> [RuntimeVersion]
}

public protocol RuntimeService {
    func listAvailable(kind: RuntimeKind) async throws -> [RuntimeVersion]
    func listInstalled(kind: RuntimeKind) throws -> [RuntimeVersion]
    func install(version: RuntimeVersion, progress: @escaping (Double) -> Void) async throws
    func activate(version: RuntimeVersion) throws
    func uninstall(version: RuntimeVersion) throws
    func currentActive(kind: RuntimeKind) -> String?
    /// Drops any in-memory caches held by the underlying system runtime
    /// detector. Callers should invoke this when the user explicitly asks
    /// for a fresh scan (e.g. tapping the refresh button).
    func invalidateSystemCaches()
}

public final class DefaultRuntimeService: NSObject, RuntimeService {
    private let root: URL
    private let providers: [RuntimeKind: VersionProvider]
    private let fileManager: FileManager
    private let systemDetector: SystemRuntimeDetector?

    public init(
        root: URL = FileSystem.envmatrixRoot,
        providers: [RuntimeKind: VersionProvider]? = nil,
        fileManager: FileManager = .default,
        systemDetector: SystemRuntimeDetector? = DefaultSystemRuntimeDetector()
    ) {
        self.root = root
        self.fileManager = fileManager
        self.systemDetector = systemDetector
        if let providers = providers {
            self.providers = providers
        } else {
            var defaults: [RuntimeKind: VersionProvider] = [:]
            defaults[.node] = NodeProvider()
            defaults[.python] = PythonProvider()
            defaults[.java] = JavaProvider()
            defaults[.go] = GoProvider()
            defaults[.rust] = RustProvider()
            defaults[.ruby] = RubyProvider()
            defaults[.php] = PhpProvider()
            defaults[.deno] = DenoProvider()
            defaults[.bun] = BunProvider()
            defaults[.dotnet] = DotnetProvider()
            defaults[.erlang] = ErlangProvider()
            self.providers = defaults
        }
        super.init()
    }

    private var versionsDir: URL {
        root.appendingPathComponent("versions", isDirectory: true)
    }

    private var shimsDir: URL {
        root.appendingPathComponent("shims", isDirectory: true)
    }

    private func versionDir(kind: RuntimeKind, version: String) -> URL {
        versionsDir
            .appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    private func ensureDirectories() throws {
        for dir in [root, versionsDir, shimsDir] {
            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - listAvailable

    public func listAvailable(kind: RuntimeKind) async throws -> [RuntimeVersion] {
        guard let provider = providers[kind] else {
            throw RuntimeServiceError.notFound
        }
        return try await provider.listAvailable()
    }

    // MARK: - listInstalled

    public func listInstalled(kind: RuntimeKind) throws -> [RuntimeVersion] {
        let kindDir = versionsDir.appendingPathComponent(kind.rawValue, isDirectory: true)
        var managed: [RuntimeVersion] = []
        if fileManager.fileExists(atPath: kindDir.path) {
            let entries = try fileManager.contentsOfDirectory(
                at: kindDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for entry in entries {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue {
                    managed.append(
                        RuntimeVersion(
                            kind: kind,
                            version: entry.lastPathComponent,
                            installPath: entry,
                            isSystem: false
                        )
                    )
                }
            }
        }

        var combined = managed
        if let detector = systemDetector {
            let managedVersions = Set(managed.map { $0.version })
            let system = detector.detect(kind: kind).filter { !managedVersions.contains($0.version) }
            combined.append(contentsOf: system)
        }

        return combined.sorted { $0.version < $1.version }
    }

    // MARK: - install

    public func install(version: RuntimeVersion, progress: @escaping (Double) -> Void) async throws {
        guard let url = version.downloadURL else {
            throw RuntimeServiceError.notFound
        }
        try ensureDirectories()

        let target = versionDir(kind: version.kind, version: version.version)
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)

        let downloader = ProgressDownloader()
        let tempURL = try await downloader.download(from: url, progress: progress)
        defer { try? fileManager.removeItem(at: tempURL) }

        try await extractTarGz(archive: tempURL, into: target)
    }

    private func extractTarGz(archive: URL, into destination: URL) async throws {
        let result = try await Shell.run(
            "/usr/bin/env",
            ["tar", "-xzf", archive.path, "-C", destination.path, "--strip-components=1"]
        )
        if result.exitCode != 0 {
            throw RuntimeServiceError.network("tar extraction failed: \(result.stderr)")
        }
    }

    // MARK: - activate

    public func activate(version: RuntimeVersion) throws {
        try ensureDirectories()
        let binaryName = version.kind.binaryName
        let source: URL
        if version.isSystem, let installPath = version.installPath {
            source = installPath
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent(binaryName)
        } else {
            source = versionDir(kind: version.kind, version: version.version)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent(binaryName)
        }
        let shim = shimsDir.appendingPathComponent(binaryName)

        if fileManager.fileExists(atPath: shim.path) || isSymlink(at: shim) {
            try fileManager.removeItem(at: shim)
        }
        try fileManager.createSymbolicLink(at: shim, withDestinationURL: source)
    }

    private func isSymlink(at url: URL) -> Bool {
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        if let type = attrs?[.type] as? FileAttributeType, type == .typeSymbolicLink {
            return true
        }
        return false
    }

    // MARK: - uninstall

    public func uninstall(version: RuntimeVersion) throws {
        if version.isSystem {
            try uninstallSystem(version: version)
        } else {
            try uninstallManaged(version: version)
        }

        // Clean up shim if it still points at the removed target.
        let binaryName = version.kind.binaryName
        let shim = shimsDir.appendingPathComponent(binaryName)
        if isSymlink(at: shim) {
            let dest = (try? fileManager.destinationOfSymbolicLink(atPath: shim.path)) ?? ""
            let installPath = version.isSystem
                ? (version.installPath?.path ?? "")
                : "/versions/\(version.kind.rawValue)/\(version.version)/"
            if !installPath.isEmpty && dest.contains(installPath) {
                try? fileManager.removeItem(at: shim)
            } else if !fileManager.fileExists(atPath: dest) {
                try? fileManager.removeItem(at: shim)
            }
        }
    }

    private func uninstallManaged(version: RuntimeVersion) throws {
        let target = versionDir(kind: version.kind, version: version.version)
        guard fileManager.fileExists(atPath: target.path) else {
            throw RuntimeServiceError.notInstalled("\(version.kind.rawValue) \(version.version)")
        }
        try fileManager.removeItem(at: target)
    }

    /// Attempts to delete a system-installed runtime by removing its install root.
    /// Falls back to a helpful error with a suggested shell command when we cannot
    /// or should not touch the target directly (e.g. requires sudo, or belongs to
    /// a package manager that maintains its own metadata).
    private func uninstallSystem(version: RuntimeVersion) throws {
        guard let root = version.installPath else {
            throw RuntimeServiceError.notInstalled(
                "\(version.kind.displayName) \(version.version)"
            )
        }
        let path = root.path
        let displayName = "\(version.kind.displayName) \(version.version)"

        // 1) Refuse to touch clearly system-critical paths — hint the user instead.
        let forbiddenPrefixes = ["/usr", "/bin", "/sbin", "/System", "/Library/Apple"]
        if forbiddenPrefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            throw RuntimeServiceError.permissionDenied(
                path: path,
                suggestion: Self.suggestion(for: version, root: root)
            )
        }

        // 2) If a supported package manager owns it, prefer routing through it.
        if let suggestion = Self.packageManagerHint(for: version, root: root) {
            throw RuntimeServiceError.permissionDenied(
                path: path,
                suggestion: suggestion
            )
        }

        // 3) Guard against the runtime living directly in $HOME (would be user data).
        let home = NSHomeDirectory()
        if path == home {
            throw RuntimeServiceError.permissionDenied(
                path: path,
                suggestion: "Refusing to remove your home directory for \(displayName)."
            )
        }

        // 4) Try to remove. If permission denied, surface a suggestion.
        do {
            try fileManager.removeItem(atPath: path)
        } catch let err as NSError where err.code == NSFileWriteNoPermissionError
                                       || err.code == 513 /* EACCES */ {
            throw RuntimeServiceError.permissionDenied(
                path: path,
                suggestion: "sudo rm -rf \"\(path)\""
            )
        }
    }

    /// Returns a suggestion command when a package manager clearly owns the path.
    /// Nil means "try to delete directly".
    private static func packageManagerHint(for version: RuntimeVersion, root: URL) -> String? {
        let p = root.path
        if p.contains("/.sdkman/candidates/") {
            let handle = root.lastPathComponent
            return "sdk uninstall java \(handle)"
        }
        if p.contains("/.jenv/versions/") {
            let handle = root.lastPathComponent
            return "jenv remove \(handle)"
        }
        if p.contains("/.nvm/versions/node/") {
            let handle = root.lastPathComponent
            return "nvm uninstall \(handle)"
        }
        if p.contains("/.goenv/versions/") {
            let handle = root.lastPathComponent
            return "goenv uninstall \(handle)"
        }
        if p.contains("/.pyenv/versions/") {
            let handle = root.lastPathComponent
            return "pyenv uninstall \(handle)"
        }
        if p.contains("/.rbenv/versions/") {
            let handle = root.lastPathComponent
            return "rbenv uninstall \(handle)"
        }
        if p.contains("/.rvm/rubies/") {
            let handle = root.lastPathComponent
            return "rvm remove \(handle)"
        }
        if p.contains("/.phpenv/versions/") {
            let handle = root.lastPathComponent
            return "phpenv uninstall \(handle)"
        }
        if p.contains("/.kerl/installations/") {
            let handle = root.lastPathComponent
            return "kerl delete installation \(handle)"
        }
        if p.hasPrefix("/opt/homebrew/") || p.hasPrefix("/usr/local/Cellar/") {
            return "brew uninstall \(version.kind.rawValue)"
        }
        return nil
    }

    /// Generic fallback suggestion when we simply refuse to touch a path.
    private static func suggestion(for version: RuntimeVersion, root: URL) -> String {
        if let hint = packageManagerHint(for: version, root: root) {
            return hint
        }
        return "sudo rm -rf \"\(root.path)\""
    }

    // MARK: - currentActive

    public func currentActive(kind: RuntimeKind) -> String? {
        // 1) EnvMatrix-managed shim wins.
        let shim = shimsDir.appendingPathComponent(kind.binaryName)
        if isSymlink(at: shim),
           let dest = try? fileManager.destinationOfSymbolicLink(atPath: shim.path) {
            let components = dest.split(separator: "/")
            if let idx = components.firstIndex(of: Substring(kind.rawValue)),
               idx + 1 < components.count,
               idx > 0,
               components[idx - 1] == "versions" {
                return String(components[idx + 1])
            }
        }
        // 2) Fallback: use the detector's fast path, which only forks a single
        //    child process for the binary resolved on the user's PATH (instead
        //    of enumerating every candidate directory).
        if let detector = systemDetector,
           let active = detector.detectActive(kind: kind) {
            return active.version
        }
        return nil
    }

    // MARK: - Caches

    public func invalidateSystemCaches() {
        systemDetector?.invalidate()
        DefaultShellPathResolver.invalidateCache()
    }
}

// MARK: - ProgressDownloader

final class ProgressDownloader: NSObject, URLSessionDownloadDelegate {
    private var progressHandler: ((Double) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?

    func download(from url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        self.progressHandler = progress
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(fraction)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Move to a stable temp location before delegate returns.
        let tempDir = FileManager.default.temporaryDirectory
        let dest = tempDir.appendingPathComponent(UUID().uuidString + ".tmp")
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            continuation?.resume(returning: dest)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error {
            continuation?.resume(throwing: error)
            continuation = nil
            session.finishTasksAndInvalidate()
        }
    }
}
