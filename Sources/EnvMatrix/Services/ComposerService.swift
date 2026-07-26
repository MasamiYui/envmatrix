import Foundation

public enum ComposerError: Error, LocalizedError {
    case commandNotFound
    case commandFailed(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandNotFound: return "The `composer` command was not found on PATH."
        case .commandFailed(let m):
            return m.isEmpty ? "The `composer` command failed." : "The `composer` command failed: \(m)"
        case .parseFailed(let m):
            return m.isEmpty ? "Failed to parse `composer` output." : "Failed to parse `composer` output: \(m)"
        }
    }
}

public protocol ComposerService {
    func isComposerAvailable() async -> Bool
    func listGlobalPackages() async throws -> [ComposerGlobalPackage]
    func uninstallGlobal(_ name: String) async throws
    func cacheStats() async throws -> ComposerCacheStats
    func cacheClean() async throws
    func readRepository() async throws -> String
    func writeRepository(_ url: String) async throws
    func presetMirrors() -> [ComposerRepositoryMirror]
}

public final class DefaultComposerService: ComposerService {
    private static let defaultRepositoryURL = "https://repo.packagist.org"

    private let shellPathResolver: ShellPathResolver
    private let fileManager: FileManager

    public init(shellPathResolver: ShellPathResolver = DefaultShellPathResolver(),
                fileManager: FileManager = .default) {
        self.shellPathResolver = shellPathResolver
        self.fileManager = fileManager
    }

    func findComposerBinary() async -> URL? {
        var searchDirs = shellPathResolver.resolvePathDirs()
        let fallbacks = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/local/opt/composer/bin",
            "/opt/homebrew/opt/composer/bin",
            NSHomeDirectory() + "/.composer/vendor/bin"
        ]
        var seen = Set(searchDirs.map { $0.path })
        for fallback in fallbacks {
            if seen.insert(fallback).inserted {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: fallback, isDirectory: &isDir), isDir.boolValue {
                    searchDirs.append(URL(fileURLWithPath: fallback))
                }
            }
        }
        for dir in searchDirs {
            let candidate = dir.appendingPathComponent("composer")
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    public func isComposerAvailable() async -> Bool { await findComposerBinary() != nil }

    public func listGlobalPackages() async throws -> [ComposerGlobalPackage] {
        guard let composer = await findComposerBinary() else { throw ComposerError.commandNotFound }
        let result = try await Shell.run(composer.path, ["global", "show", "--format=json", "--no-plugins"])
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if stdout.isEmpty && result.exitCode != 0 {
            throw ComposerError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let data = stdout.data(using: .utf8) else {
            throw ComposerError.parseFailed("stdout is not valid UTF-8")
        }
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ComposerError.parseFailed(error.localizedDescription)
        }
        guard let root = jsonObject as? [String: Any] else {
            throw ComposerError.parseFailed("root is not a JSON object")
        }
        let installed = (root["installed"] as? [[String: Any]]) ?? []
        var packages: [ComposerGlobalPackage] = []
        for entry in installed {
            guard let name = entry["name"] as? String,
                  let version = entry["version"] as? String else { continue }
            let path = entry["path"] as? String
            packages.append(ComposerGlobalPackage(name: name, version: version, path: path))
        }
        packages.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return packages
    }

    public func uninstallGlobal(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ComposerError.commandFailed("Package name must not be empty") }
        guard let composer = await findComposerBinary() else { throw ComposerError.commandNotFound }
        let result = try await Shell.run(composer.path, ["global", "remove", trimmed, "--no-interaction"])
        if result.exitCode != 0 {
            throw ComposerError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func cacheStats() async throws -> ComposerCacheStats {
        let path = NSHomeDirectory() + "/Library/Caches/composer"
        var isDir: ObjCBool = false
        var chosen = path
        if !(fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue) {
            let fallback = NSHomeDirectory() + "/.composer/cache"
            if fileManager.fileExists(atPath: fallback, isDirectory: &isDir), isDir.boolValue {
                chosen = fallback
            } else {
                return ComposerCacheStats(path: path, sizeBytes: 0)
            }
        }
        let final = chosen
        let size: Int64 = await Task.detached(priority: .utility) { [fileManager] in
            DefaultGemService.directorySize(at: URL(fileURLWithPath: final), fileManager: fileManager)
        }.value
        return ComposerCacheStats(path: final, sizeBytes: size)
    }

    public func cacheClean() async throws {
        guard let composer = await findComposerBinary() else { throw ComposerError.commandNotFound }
        let result = try await Shell.run(composer.path, ["clear-cache"])
        if result.exitCode != 0 {
            throw ComposerError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func readRepository() async throws -> String {
        guard let composer = await findComposerBinary() else { throw ComposerError.commandNotFound }
        let result = try await Shell.run(composer.path, ["config", "-g", "repos.packagist.url"])
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty { return out }
        return Self.defaultRepositoryURL
    }

    public func writeRepository(_ url: String) async throws {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ComposerError.commandFailed("Repository URL must not be empty") }
        guard let composer = await findComposerBinary() else { throw ComposerError.commandNotFound }
        let result = try await Shell.run(composer.path, ["config", "-g", "repo.packagist", "composer", trimmed])
        if result.exitCode != 0 {
            throw ComposerError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func presetMirrors() -> [ComposerRepositoryMirror] {
        [
            ComposerRepositoryMirror(id: "aliyun", name: "Alibaba Cloud", url: "https://mirrors.aliyun.com/composer/", isPreset: true),
            ComposerRepositoryMirror(id: "tencent", name: "Tencent Cloud", url: "https://mirrors.cloud.tencent.com/composer/", isPreset: true),
            ComposerRepositoryMirror(id: "huawei", name: "HuaweiCloud", url: "https://mirrors.huaweicloud.com/repository/php/", isPreset: true),
            ComposerRepositoryMirror(id: "packagist", name: "Packagist Official", url: "https://repo.packagist.org", isPreset: true)
        ]
    }
}
