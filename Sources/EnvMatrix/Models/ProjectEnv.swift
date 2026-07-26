import Foundation

/// The kind of on-disk project environment we surface to the user.
///
/// The scanner only enumerates directories that look reasonably confident:
///   * `venv`         — a Python virtual environment (contains `pyvenv.cfg`).
///   * `nodeModules`  — a `node_modules` directory whose sibling holds a
///                      `package.json` (guards against unrelated folders that
///                      happen to be named "node_modules").
public enum ProjectEnvKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case venv
    case nodeModules

    public var id: String { rawValue }

    /// Human-friendly label used in filter chips / segmented controls.
    public var shortLabel: String {
        switch self {
        case .venv: return "Python venv"
        case .nodeModules: return "node_modules"
        }
    }
}

/// The JavaScript package manager we associate with a `node_modules` folder,
/// inferred from the sibling lockfile. Falls back to `.unknown` if the project
/// root has no recognisable lockfile.
public enum JSPackageManager: String, Sendable, Codable, CaseIterable, Identifiable {
    case npm
    case pnpm
    case yarn
    case bun
    case unknown

    public var id: String { rawValue }

    /// The lockfile filename that identifies this package manager.
    /// `nil` for `.unknown`.
    public var lockfileName: String? {
        switch self {
        case .npm: return "package-lock.json"
        case .pnpm: return "pnpm-lock.yaml"
        case .yarn: return "yarn.lock"
        case .bun: return "bun.lockb"
        case .unknown: return nil
        }
    }

    public var installArgs: [String] {
        switch self {
        case .npm: return ["install"]
        case .pnpm: return ["install"]
        case .yarn: return ["install"]
        case .bun: return ["install"]
        case .unknown: return ["install"]
        }
    }
}

/// A single discovered project environment on the local filesystem.
///
/// `id` is derived from the absolute path so SwiftUI diffs stay stable across
/// rescans even if the ordering changes.
public struct ProjectEnvironment: Identifiable, Sendable, Hashable {
    public let kind: ProjectEnvKind
    /// The environment directory itself (e.g. `~/Projects/foo/.venv`
    /// or `~/Projects/foo/node_modules`).
    public let url: URL
    /// The project root, i.e. the directory that *contains* the environment.
    /// For a venv this is the folder holding `pyvenv.cfg`'s parent; for
    /// node_modules it's the folder holding `package.json`.
    public let projectRoot: URL
    /// Size in bytes. `nil` while still being computed / on failure.
    public let sizeBytes: Int64?
    /// venv only — the Python interpreter version reported by `pyvenv.cfg`.
    public let pythonVersion: String?
    /// node_modules only — the detected package manager.
    public let packageManager: JSPackageManager?
    /// Best-effort modification date of the environment directory.
    public let modifiedAt: Date?

    public var id: String { "\(kind.rawValue):\(url.path)" }

    /// Display name shown as the row title — the project directory basename
    /// combined with a tiny suffix to disambiguate multiple envs in the same
    /// project (e.g. `myapp / .venv`).
    public var displayTitle: String {
        let project = projectRoot.lastPathComponent
        let env = url.lastPathComponent
        if project.isEmpty { return env }
        return "\(project) / \(env)"
    }
}

/// Aggregated snapshot returned by a scan.
public struct ProjectEnvInventory: Sendable {
    public let environments: [ProjectEnvironment]
    /// Roots we actually walked during this scan (skipping any that no longer
    /// exist).
    public let rootsScanned: [URL]
    /// Total bytes across every environment — used in the header summary.
    public let totalBytes: Int64
    /// Wall-clock scan duration in seconds. Displayed in the toolbar so the
    /// user has a sense of how expensive a rescan is.
    public let scanDuration: TimeInterval

    public static let empty = ProjectEnvInventory(
        environments: [],
        rootsScanned: [],
        totalBytes: 0,
        scanDuration: 0
    )

    public init(
        environments: [ProjectEnvironment],
        rootsScanned: [URL],
        totalBytes: Int64,
        scanDuration: TimeInterval
    ) {
        self.environments = environments
        self.rootsScanned = rootsScanned
        self.totalBytes = totalBytes
        self.scanDuration = scanDuration
    }
}

/// Long-running operations we perform on an environment.
public enum ProjectEnvOperation: Sendable, Equatable {
    /// Move the environment to the Trash (recoverable).
    case delete(ProjectEnvironment)
    /// node_modules only — delete then re-install with the detected pm.
    case reinstall(ProjectEnvironment)
}

/// Errors raised by the scanner or ops layer.
public enum ProjectEnvError: Error, LocalizedError {
    case rootUnreadable(URL)
    case deleteFailed(URL, underlying: String)
    case reinstallUnsupported(reason: String)
    case commandFailed(command: String, stderr: String, exitCode: Int32)

    public var errorDescription: String? {
        switch self {
        case .rootUnreadable(let url):
            return "Cannot read \(url.path). Grant Full Disk Access or pick a different root."
        case .deleteFailed(let url, let msg):
            return "Failed to move \(url.lastPathComponent) to Trash: \(msg)"
        case .reinstallUnsupported(let r):
            return "Reinstall is not supported for this environment: \(r)"
        case .commandFailed(let cmd, let err, let code):
            return "`\(cmd)` exited with code \(code): \(err.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

/// Human-readable byte count formatter shared by views.
public enum ByteFormatter {
    public static func format(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useMB, .useGB, .useKB]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: bytes)
    }
}
