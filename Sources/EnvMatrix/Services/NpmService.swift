import Foundation

public enum NpmError: Error, LocalizedError {
    case commandNotFound
    case commandFailed(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandNotFound:
            return "The `npm` command was not found on PATH."
        case .commandFailed(let message):
            if message.isEmpty {
                return "The `npm` command failed."
            }
            return "The `npm` command failed: \(message)"
        case .parseFailed(let message):
            if message.isEmpty {
                return "Failed to parse `npm` output."
            }
            return "Failed to parse `npm` output: \(message)"
        }
    }
}

public protocol NpmService {
    func isNpmAvailable() async -> Bool
    func listGlobalPackages() async throws -> [NodeGlobalPackage]
    func uninstallGlobal(_ name: String) async throws
    func cacheStats() async throws -> NodeCacheStats
    func cacheClean() async throws
}

public final class DefaultNpmService: NpmService {
    private let shellPathResolver: ShellPathResolver
    private let fileManager: FileManager

    public init(
        shellPathResolver: ShellPathResolver = DefaultShellPathResolver(),
        fileManager: FileManager = .default
    ) {
        self.shellPathResolver = shellPathResolver
        self.fileManager = fileManager
    }

    func findNpmBinary() async -> URL? {
        var searchDirs = shellPathResolver.resolvePathDirs()
        let fallbacks = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/local/opt/node/bin"
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
            let candidate = dir.appendingPathComponent("npm")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    public func isNpmAvailable() async -> Bool {
        await findNpmBinary() != nil
    }

    public func listGlobalPackages() async throws -> [NodeGlobalPackage] {
        guard let npm = await findNpmBinary() else {
            throw NpmError.commandNotFound
        }
        let result = try await Shell.run(npm.path, ["ls", "-g", "--depth=0", "--json"])
        let stdout = result.stdout
        let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // `npm ls` may exit non-zero when peer deps are missing but still emits
        // valid JSON on stdout. Only fail if stdout is empty AND non-zero exit.
        if trimmedStdout.isEmpty && result.exitCode != 0 {
            throw NpmError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        guard let data = trimmedStdout.data(using: .utf8) else {
            throw NpmError.parseFailed("stdout is not valid UTF-8")
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw NpmError.parseFailed(error.localizedDescription)
        }

        guard let root = jsonObject as? [String: Any] else {
            throw NpmError.parseFailed("root is not a JSON object")
        }

        guard let dependencies = root["dependencies"] as? [String: Any] else {
            return []
        }

        var packages: [NodeGlobalPackage] = []
        for (name, rawEntry) in dependencies {
            guard let entry = rawEntry as? [String: Any] else { continue }
            guard let version = entry["version"] as? String,
                  !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let path = entry["path"] as? String
            packages.append(NodeGlobalPackage(name: name, version: version, path: path))
        }

        packages.sort { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return packages
    }

    public func uninstallGlobal(_ name: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NpmError.commandFailed("Package name must not be empty")
        }
        guard let npm = await findNpmBinary() else {
            throw NpmError.commandNotFound
        }
        let result = try await Shell.run(npm.path, ["uninstall", "-g", trimmedName])
        if result.exitCode != 0 {
            throw NpmError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    public func cacheStats() async throws -> NodeCacheStats {
        let path = NSHomeDirectory() + "/.npm/_cacache"
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return NodeCacheStats(path: path, sizeBytes: 0)
        }
        let total = directorySize(at: URL(fileURLWithPath: path))
        return NodeCacheStats(path: path, sizeBytes: total)
    }

    public func cacheClean() async throws {
        guard let npm = await findNpmBinary() else {
            throw NpmError.commandNotFound
        }
        let result = try await Shell.run(npm.path, ["cache", "clean", "--force"])
        if result.exitCode != 0 {
            throw NpmError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
            )
            if let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize {
                total += Int64(size)
            }
        }
        return total
    }
}
