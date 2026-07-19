import Foundation

/// Kind of Homebrew package.
public enum BrewPackageKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case formula
    case cask

    public var id: String { rawValue }
}

/// A single Homebrew package (formula or cask) as reported by
/// `brew info --installed --json=v2`.
///
/// We deliberately keep only the fields we actually render — the JSON payload
/// is huge and re-decoding everything makes the app feel sluggish.
public struct BrewPackage: Identifiable, Sendable, Hashable {
    public let kind: BrewPackageKind
    /// Formula: `name` (e.g. `bat`). Cask: `token` (e.g. `cc-switch`).
    public let name: String
    /// Formula: `full_name`. Cask: `full_token`. May be namespaced by tap.
    public let fullName: String
    /// Short description (may be `nil` for casks with no `desc`).
    public let description: String?
    public let homepage: String?
    /// Installed version (best-effort). For formulae we take
    /// `installed[0].version`; for casks we use the `installed` string field.
    public let installedVersion: String?
    /// Latest version reported by `outdated` (only populated when outdated).
    public let latestVersion: String?
    /// Formula: `installed[0].installed_on_request`. Casks: always `true`.
    /// Used to distinguish user-requested vs. transitively-installed packages.
    public let installedOnRequest: Bool
    public let isOutdated: Bool
    public let isPinned: Bool
    public let isDeprecated: Bool
    public let deprecationReason: String?
    /// Cask-specific: whether the app self-updates.
    public let autoUpdates: Bool
    /// Cask-specific: install epoch (`installed_time`). `nil` for formulae.
    public let installedAt: Date?
    /// Runtime dependencies (formula only). Names as reported by brew.
    public let dependencies: [String]

    public var id: String { "\(kind.rawValue):\(fullName)" }
}

/// Aggregated snapshot of the local Homebrew installation.
public struct BrewInventory: Sendable {
    public let formulae: [BrewPackage]
    public let casks: [BrewPackage]
    public let outdatedCount: Int
    public let brewPath: String
    public let brewVersion: String

    public static let empty = BrewInventory(
        formulae: [],
        casks: [],
        outdatedCount: 0,
        brewPath: "",
        brewVersion: ""
    )

    public init(
        formulae: [BrewPackage],
        casks: [BrewPackage],
        outdatedCount: Int,
        brewPath: String,
        brewVersion: String
    ) {
        self.formulae = formulae
        self.casks = casks
        self.outdatedCount = outdatedCount
        self.brewPath = brewPath
        self.brewVersion = brewVersion
    }
}

/// Long-running brew operation types.
public enum BrewOperation: Sendable, Equatable {
    case install(String, BrewPackageKind)
    case uninstall(String, BrewPackageKind)
    case upgrade(String)
    case upgradeAll
    case pin(String)
    case unpin(String)
    case cleanup
    case update

    public var displayLabel: String {
        switch self {
        case .install(let n, _): return "install \(n)"
        case .uninstall(let n, _): return "uninstall \(n)"
        case .upgrade(let n): return "upgrade \(n)"
        case .upgradeAll: return "upgrade --all"
        case .pin(let n): return "pin \(n)"
        case .unpin(let n): return "unpin \(n)"
        case .cleanup: return "cleanup"
        case .update: return "update"
        }
    }
}

/// Errors raised by `HomebrewService`.
public enum BrewError: Error, LocalizedError {
    case notInstalled
    case commandFailed(command: String, stderr: String, exitCode: Int32)
    case parseFailure(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Homebrew was not found on this system. Install it from https://brew.sh first."
        case .commandFailed(let cmd, let err, let code):
            return "`brew \(cmd)` exited with code \(code): \(err.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .parseFailure(let msg):
            return "Failed to parse brew output: \(msg)"
        }
    }
}
