import Foundation

public enum GoEnvError: Error, LocalizedError {
    case commandNotFound
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandNotFound:
            return "The `go` command was not found on PATH."
        case .commandFailed(let message):
            if message.isEmpty {
                return "The `go` command failed."
            }
            return "The `go` command failed: \(message)"
        }
    }
}

public protocol GoEnvService {
    func readProxy() async throws -> String
    func writeProxy(_ value: String) async throws
    func isGoAvailable() async -> Bool
    func presetProxies() -> [GoProxyPreset]
}

public final class DefaultGoEnvService: GoEnvService {
    private let shellPathResolver: ShellPathResolver
    private let fileManager: FileManager

    public init(shellPathResolver: ShellPathResolver = DefaultShellPathResolver()) {
        self.shellPathResolver = shellPathResolver
        self.fileManager = .default
    }

    func findGoBinary() async -> URL? {
        var searchDirs = shellPathResolver.resolvePathDirs()
        let fallbacks = [
            "/usr/local/go/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/opt/go/bin"
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
            let candidate = dir.appendingPathComponent("go")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    public func isGoAvailable() async -> Bool {
        await findGoBinary() != nil
    }

    public func readProxy() async throws -> String {
        guard let go = await findGoBinary() else {
            throw GoEnvError.commandNotFound
        }
        let result = try await Shell.run(go.path, ["env", "GOPROXY"])
        if result.exitCode != 0 {
            throw GoEnvError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "https://proxy.golang.org,direct"
        }
        return trimmed
    }

    public func writeProxy(_ value: String) async throws {
        guard let go = await findGoBinary() else {
            throw GoEnvError.commandNotFound
        }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty {
            throw GoEnvError.commandFailed("GOPROXY value must not be empty")
        }
        let result = try await Shell.run(go.path, ["env", "-w", "GOPROXY=\(trimmedValue)"])
        if result.exitCode != 0 {
            throw GoEnvError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    public func presetProxies() -> [GoProxyPreset] {
        [
            GoProxyPreset(id: "direct", name: "Direct (No Proxy)", value: "direct"),
            GoProxyPreset(id: "goproxy.cn", name: "goproxy.cn (Qiniu)", value: "https://goproxy.cn,direct"),
            GoProxyPreset(id: "goproxy.io", name: "goproxy.io", value: "https://goproxy.io,direct"),
            GoProxyPreset(id: "aliyun", name: "Aliyun", value: "https://mirrors.aliyun.com/goproxy/,direct"),
            GoProxyPreset(id: "tencent", name: "Tencent Cloud", value: "https://mirrors.cloud.tencent.com/go/,direct")
        ]
    }
}
