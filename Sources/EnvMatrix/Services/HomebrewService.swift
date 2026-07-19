import Foundation

/// Public protocol so views/tests can swap in a fake implementation.
public protocol HomebrewService: AnyObject {
    /// `true` iff a usable `brew` binary was discovered.
    var isAvailable: Bool { get }
    /// Path to the discovered `brew` executable, or empty string.
    var brewPath: String { get }

    func inventory(forceRefresh: Bool) async throws -> BrewInventory
    func run(_ operation: BrewOperation) async throws -> String
    func invalidateCache()
}

/// Default `HomebrewService` implementation.
///
/// The class is intentionally simple: everything routes through `brew` on
/// disk, output is JSON where available, and results are cached in memory
/// until the caller (typically the view model) asks for a refresh.
public final class DefaultHomebrewService: HomebrewService {
    public let brewPath: String
    public var isAvailable: Bool { !brewPath.isEmpty }

    private var brewVersion: String = ""
    private let cacheLock = NSLock()
    private var cachedInventory: BrewInventory?

    public init(explicitPath: String? = nil) {
        if let p = explicitPath, FileManager.default.isExecutableFile(atPath: p) {
            self.brewPath = p
            return
        }
        // Homebrew canonically lives at one of these two locations.
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        self.brewPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }

    // MARK: - Public API

    public func inventory(forceRefresh: Bool = false) async throws -> BrewInventory {
        if !forceRefresh, let cached = readCache() {
            return cached
        }
        guard isAvailable else { throw BrewError.notInstalled }

        // Run info + outdated concurrently; outdated is cheap once info's cache is warm.
        async let infoTask = runBrewJSON(["info", "--installed", "--json=v2"])
        async let outdatedTask = runBrewJSON(["outdated", "--json=v2", "--greedy"])
        async let versionTask = runBrew(["--version"])

        let infoData = try await infoTask
        let outdatedData = try await outdatedTask
        let versionOut = (try? await versionTask.stdout) ?? ""

        let outdatedIndex = try parseOutdatedIndex(from: outdatedData)
        let (formulae, casks) = try parseInstalled(from: infoData, outdatedIndex: outdatedIndex)

        let outdatedCount = formulae.filter(\.isOutdated).count + casks.filter(\.isOutdated).count
        let version = versionOut
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""

        let inv = BrewInventory(
            formulae: formulae.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            casks: casks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            outdatedCount: outdatedCount,
            brewPath: brewPath,
            brewVersion: version
        )
        writeCache(inv)
        return inv
    }

    public func run(_ operation: BrewOperation) async throws -> String {
        guard isAvailable else { throw BrewError.notInstalled }
        let args = arguments(for: operation)
        let res = try await runBrew(args)
        if res.exitCode != 0 {
            throw BrewError.commandFailed(
                command: args.joined(separator: " "),
                stderr: res.stderr.isEmpty ? res.stdout : res.stderr,
                exitCode: res.exitCode
            )
        }
        invalidateCache()
        return res.stdout
    }

    public func invalidateCache() {
        cacheLock.lock()
        cachedInventory = nil
        cacheLock.unlock()
    }

    // MARK: - Cache

    private func readCache() -> BrewInventory? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedInventory
    }

    private func writeCache(_ inv: BrewInventory) {
        cacheLock.lock()
        cachedInventory = inv
        cacheLock.unlock()
    }

    // MARK: - Argument builder

    private func arguments(for op: BrewOperation) -> [String] {
        switch op {
        case .install(let name, let kind):
            return kind == .cask ? ["install", "--cask", name] : ["install", name]
        case .uninstall(let name, let kind):
            return kind == .cask ? ["uninstall", "--cask", name] : ["uninstall", name]
        case .upgrade(let name):
            return ["upgrade", name]
        case .upgradeAll:
            return ["upgrade"]
        case .pin(let name):
            return ["pin", name]
        case .unpin(let name):
            return ["unpin", name]
        case .cleanup:
            return ["cleanup"]
        case .update:
            return ["update"]
        }
    }

    // MARK: - Shell wiring

    /// `brew` inspects `HOMEBREW_*` env vars and can be very slow if the
    /// user's login shell exports huge additions. We pass a minimal env
    /// so the CLI always behaves the same way regardless of the caller's PATH.
    private func minimalEnv() -> [String: String] {
        [
            "HOME": NSHomeDirectory(),
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_ENV_HINTS": "1",
            "HOMEBREW_NO_ANALYTICS": "1"
        ]
    }

    private func runBrew(_ args: [String]) async throws -> ShellResult {
        try await Shell.run(brewPath, args, env: minimalEnv())
    }

    private func runBrewJSON(_ args: [String]) async throws -> Data {
        let res = try await runBrew(args)
        if res.exitCode != 0 {
            throw BrewError.commandFailed(
                command: args.joined(separator: " "),
                stderr: res.stderr,
                exitCode: res.exitCode
            )
        }
        return Data(res.stdout.utf8)
    }

    // MARK: - JSON parsing

    /// Extract `name -> current_version` from `brew outdated --json=v2`.
    /// We intentionally use `JSONSerialization` (untyped) here — the payload
    /// is small and mixing `Decodable` structs across brew CLI generations
    /// has bitten us before.
    private func parseOutdatedIndex(from data: Data) throws -> [String: String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrewError.parseFailure("outdated: root is not an object")
        }
        var index: [String: String] = [:]
        for key in ["formulae", "casks"] {
            let arr = root[key] as? [[String: Any]] ?? []
            for item in arr {
                if let name = item["name"] as? String,
                   let current = item["current_version"] as? String {
                    index[name] = current
                }
            }
        }
        return index
    }

    private func parseInstalled(
        from data: Data,
        outdatedIndex: [String: String]
    ) throws -> (formulae: [BrewPackage], casks: [BrewPackage]) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrewError.parseFailure("info: root is not an object")
        }
        let formulae = (root["formulae"] as? [[String: Any]] ?? []).map {
            Self.decodeFormula($0, outdatedIndex: outdatedIndex)
        }
        let casks = (root["casks"] as? [[String: Any]] ?? []).map {
            Self.decodeCask($0, outdatedIndex: outdatedIndex)
        }
        return (formulae, casks)
    }

    private static func decodeFormula(
        _ obj: [String: Any],
        outdatedIndex: [String: String]
    ) -> BrewPackage {
        let name = (obj["name"] as? String) ?? ""
        let fullName = (obj["full_name"] as? String) ?? name
        let installedArr = (obj["installed"] as? [[String: Any]]) ?? []
        let installed = installedArr.first
        let version = installed?["version"] as? String
        let onRequest = (installed?["installed_on_request"] as? Bool) ?? true
        let outdated = (obj["outdated"] as? Bool) ?? false
        let pinned = (obj["pinned"] as? Bool) ?? false
        let deprecated = (obj["deprecated"] as? Bool) ?? false
        let deprecationReason = obj["deprecation_reason"] as? String
        let dependencies = (obj["dependencies"] as? [String]) ?? []
        return BrewPackage(
            kind: .formula,
            name: name,
            fullName: fullName,
            description: obj["desc"] as? String,
            homepage: obj["homepage"] as? String,
            installedVersion: version,
            latestVersion: outdatedIndex[name],
            installedOnRequest: onRequest,
            isOutdated: outdated,
            isPinned: pinned,
            isDeprecated: deprecated,
            deprecationReason: deprecationReason,
            autoUpdates: false,
            installedAt: nil,
            dependencies: dependencies
        )
    }

    private static func decodeCask(
        _ obj: [String: Any],
        outdatedIndex: [String: String]
    ) -> BrewPackage {
        let token = (obj["token"] as? String) ?? ""
        let fullToken = (obj["full_token"] as? String) ?? token
        // `name` on a cask is an array of display names; the first is preferred.
        let nameArr = obj["name"] as? [String]
        let displayName = nameArr?.first ?? token
        let installed = obj["installed"] as? String
        let outdated = (obj["outdated"] as? Bool) ?? false
        let pinned = (obj["pinned"] as? Bool) ?? false
        let deprecated = (obj["deprecated"] as? Bool) ?? false
        let deprecationReason = obj["deprecation_reason"] as? String
        let autoUpdates = (obj["auto_updates"] as? Bool) ?? false
        let installedTime = obj["installed_time"] as? Double
        return BrewPackage(
            kind: .cask,
            name: token,
            fullName: fullToken,
            description: (obj["desc"] as? String) ?? displayName,
            homepage: obj["homepage"] as? String,
            installedVersion: installed,
            latestVersion: outdatedIndex[token],
            installedOnRequest: true,
            isOutdated: outdated,
            isPinned: pinned,
            isDeprecated: deprecated,
            deprecationReason: deprecationReason,
            autoUpdates: autoUpdates,
            installedAt: installedTime.map { Date(timeIntervalSince1970: $0) },
            dependencies: []
        )
    }
}
