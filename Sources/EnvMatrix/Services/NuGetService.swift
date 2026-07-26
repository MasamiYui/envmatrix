import Foundation

public enum NuGetError: Error, LocalizedError {
    case commandNotFound
    case commandFailed(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandNotFound: return "The `dotnet` command was not found on PATH."
        case .commandFailed(let m):
            return m.isEmpty ? "The `dotnet` command failed." : "The `dotnet` command failed: \(m)"
        case .parseFailed(let m):
            return m.isEmpty ? "Failed to parse `dotnet` output." : "Failed to parse `dotnet` output: \(m)"
        }
    }
}

public protocol NuGetService {
    func isDotnetAvailable() async -> Bool
    func listGlobalTools() async throws -> [DotnetGlobalTool]
    func uninstallGlobalTool(_ name: String) async throws
    func cacheStats() async throws -> DotnetCacheStats
    func cacheClean() async throws
    func readEnabledSources() async throws -> [(name: String, url: String)]
    func setPrimarySource(name: String, url: String) async throws
    func presetMirrors() -> [NuGetSourceMirror]
}

public final class DefaultNuGetService: NuGetService {
    private let shellPathResolver: ShellPathResolver
    private let fileManager: FileManager

    public init(shellPathResolver: ShellPathResolver = DefaultShellPathResolver(),
                fileManager: FileManager = .default) {
        self.shellPathResolver = shellPathResolver
        self.fileManager = fileManager
    }

    func findDotnetBinary() async -> URL? {
        var searchDirs = shellPathResolver.resolvePathDirs()
        let fallbacks = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/local/share/dotnet",
            "/opt/homebrew/opt/dotnet/bin",
            NSHomeDirectory() + "/.dotnet"
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
            let candidate = dir.appendingPathComponent("dotnet")
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    public func isDotnetAvailable() async -> Bool { await findDotnetBinary() != nil }

    public func listGlobalTools() async throws -> [DotnetGlobalTool] {
        guard let dotnet = await findDotnetBinary() else { throw NuGetError.commandNotFound }
        let result = try await Shell.run(dotnet.path, ["tool", "list", "--global"])
        let stdout = result.stdout
        if stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && result.exitCode != 0 {
            throw NuGetError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var tools: [DotnetGlobalTool] = []
        let lines = stdout.split(separator: "\n").map(String.init)
        guard lines.count > 2 else { return [] }
        for line in lines.dropFirst(2) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map { String($0) }
                .filter { !$0.isEmpty }
            if parts.count >= 2 {
                let name = parts[0]
                let version = parts[1]
                let commands = parts.count >= 3 ? parts[2...].joined(separator: " ") : nil
                tools.append(DotnetGlobalTool(name: name, version: version, commands: commands))
            }
        }
        tools.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return tools
    }

    public func uninstallGlobalTool(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NuGetError.commandFailed("Tool name must not be empty") }
        guard let dotnet = await findDotnetBinary() else { throw NuGetError.commandNotFound }
        let result = try await Shell.run(dotnet.path, ["tool", "uninstall", "--global", trimmed])
        if result.exitCode != 0 {
            throw NuGetError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func cacheStats() async throws -> DotnetCacheStats {
        let candidates = [
            NSHomeDirectory() + "/.nuget/packages",
            NSHomeDirectory() + "/Library/Caches/NuGet/v3-cache"
        ]
        var chosenPath = candidates[0]
        for c in candidates {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: c, isDirectory: &isDir), isDir.boolValue {
                chosenPath = c
                break
            }
        }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: chosenPath, isDirectory: &isDir), isDir.boolValue else {
            return DotnetCacheStats(path: chosenPath, sizeBytes: 0)
        }
        let path = chosenPath
        let size: Int64 = await Task.detached(priority: .utility) { [fileManager] in
            DefaultGemService.directorySize(at: URL(fileURLWithPath: path), fileManager: fileManager)
        }.value
        return DotnetCacheStats(path: path, sizeBytes: size)
    }

    public func cacheClean() async throws {
        guard let dotnet = await findDotnetBinary() else { throw NuGetError.commandNotFound }
        let result = try await Shell.run(dotnet.path, ["nuget", "locals", "all", "--clear"])
        if result.exitCode != 0 {
            throw NuGetError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func readEnabledSources() async throws -> [(name: String, url: String)] {
        guard let dotnet = await findDotnetBinary() else { throw NuGetError.commandNotFound }
        let result = try await Shell.run(dotnet.path, ["nuget", "list", "source", "--format", "short"])
        if result.exitCode != 0 && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NuGetError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var sources: [(String, String)] = []
        for rawLine in result.stdout.split(separator: "\n") {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard line.hasPrefix("E") else { continue }
            let rest = line.dropFirst().trimmingCharacters(in: .whitespaces)
            let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            if parts.count == 2 {
                sources.append((parts[0], parts[1]))
            } else if parts.count == 1 {
                sources.append(("", parts[0]))
            }
        }
        return sources
    }

    public func setPrimarySource(name: String, url: String) async throws {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedName.isEmpty else {
            throw NuGetError.commandFailed("Name and URL must not be empty")
        }
        guard let dotnet = await findDotnetBinary() else { throw NuGetError.commandNotFound }
        _ = try? await Shell.run(dotnet.path, ["nuget", "remove", "source", trimmedName])
        let add = try await Shell.run(dotnet.path, ["nuget", "add", "source", trimmedURL, "--name", trimmedName])
        if add.exitCode != 0 {
            throw NuGetError.commandFailed(add.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func presetMirrors() -> [NuGetSourceMirror] {
        [
            NuGetSourceMirror(id: "huaweicloud", name: "HuaweiCloud", url: "https://mirrors.huaweicloud.com/repository/nuget/v3/index.json", isPreset: true),
            NuGetSourceMirror(id: "tencent", name: "Tencent Cloud", url: "https://mirrors.tencent.com/nuget/v3/index.json", isPreset: true),
            NuGetSourceMirror(id: "azure-devops", name: "Azure DevOps CN", url: "https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-public/nuget/v3/index.json", isPreset: true),
            NuGetSourceMirror(id: "nuget-org", name: "NuGet.org Official", url: "https://api.nuget.org/v3/index.json", isPreset: true)
        ]
    }
}
