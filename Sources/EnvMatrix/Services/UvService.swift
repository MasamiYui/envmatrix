import Foundation

public enum UvError: Error, LocalizedError {
    case commandNotFound
    case commandFailed(String)
    case parseFailed(String)
    case configError(String)

    public var errorDescription: String? {
        switch self {
        case .commandNotFound:
            return "The `uv` command was not found on PATH."
        case .commandFailed(let message):
            if message.isEmpty {
                return "The `uv` command failed."
            }
            return "The `uv` command failed: \(message)"
        case .parseFailed(let message):
            if message.isEmpty {
                return "Failed to parse `uv` output."
            }
            return "Failed to parse `uv` output: \(message)"
        case .configError(let message):
            if message.isEmpty {
                return "Failed to access the uv.toml file."
            }
            return "Failed to access the uv.toml file: \(message)"
        }
    }
}

public protocol UvService {
    func isAvailable() async -> Bool
    func listGlobalTools() async throws -> [UvTool]
    func uninstallTool(name: String) async throws
    func cacheStats() async throws -> UvCacheStats
    func cacheClean() async throws
}

public protocol UvConfigService {
    var uvConfigURL: URL { get }
    func currentRegistry() throws -> String
    func setRegistry(url: String) throws
    func presetRegistries() -> [UvRegistryPreset]
}

public final class DefaultUvService: UvService {
    private let shellPathResolver: ShellPathResolver
    private let fileManager: FileManager

    public init(
        shellPathResolver: ShellPathResolver = DefaultShellPathResolver(),
        fileManager: FileManager = .default
    ) {
        self.shellPathResolver = shellPathResolver
        self.fileManager = fileManager
    }

    func findBinary() async -> URL? {
        var searchDirs = shellPathResolver.resolvePathDirs()
        let fallbacks = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin"),
            (NSHomeDirectory() as NSString).appendingPathComponent(".cargo/bin")
        ]
        var seen = Set(searchDirs.map { $0.path })
        for fallback in fallbacks {
            let expanded = (fallback as NSString).expandingTildeInPath
            if seen.insert(expanded).inserted {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                    searchDirs.append(URL(fileURLWithPath: expanded))
                }
            }
        }

        for dir in searchDirs {
            let candidate = dir.appendingPathComponent("uv")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    public func isAvailable() async -> Bool {
        await findBinary() != nil
    }

    public func listGlobalTools() async throws -> [UvTool] {
        guard let uv = await findBinary() else {
            throw UvError.commandNotFound
        }
        let result = try await Shell.run(uv.path, ["tool", "list"])
        let stdout = result.stdout
        if stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && result.exitCode != 0 {
            throw UvError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return Self.parseToolList(stdout: stdout)
    }

    internal static func parseToolList(stdout: String) -> [UvTool] {
        var tools: [UvTool] = []
        let lines = stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for rawLine in lines {
            if rawLine.isEmpty { continue }
            // Sub-entries are indented (leading whitespace) — skip them.
            if let first = rawLine.first, first == " " || first == "\t" {
                continue
            }
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // Expect the format: "<name> v<version>"
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let name = parts.first, !name.isEmpty else { continue }

            var version: String?
            if parts.count >= 2 {
                let second = parts[1]
                if second.hasPrefix("v") {
                    let ver = String(second.dropFirst())
                    if !ver.isEmpty { version = ver }
                } else {
                    version = second
                }
            }
            tools.append(UvTool(name: name, version: version))
        }
        return tools
    }

    public func uninstallTool(name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw UvError.commandFailed("Tool name must not be empty")
        }
        guard let uv = await findBinary() else {
            throw UvError.commandNotFound
        }
        let result = try await Shell.run(uv.path, ["tool", "uninstall", trimmed])
        if result.exitCode != 0 {
            throw UvError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    public func cacheStats() async throws -> UvCacheStats {
        guard let uv = await findBinary() else {
            throw UvError.commandNotFound
        }
        let result = try await Shell.run(uv.path, ["cache", "dir"])
        if result.exitCode != 0 {
            throw UvError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw UvError.parseFailed("cache dir is empty")
        }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return UvCacheStats(path: path, sizeBytes: 0)
        }
        let total = directorySize(at: URL(fileURLWithPath: path))
        return UvCacheStats(path: path, sizeBytes: total)
    }

    public func cacheClean() async throws {
        guard let uv = await findBinary() else {
            throw UvError.commandNotFound
        }
        let result = try await Shell.run(uv.path, ["cache", "clean"])
        if result.exitCode != 0 {
            throw UvError.commandFailed(
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

public final class DefaultUvConfigService: UvConfigService {
    private static let defaultRegistry = "https://pypi.org/simple"

    public let uvConfigURL: URL
    private let fileManager: FileManager

    public init(uvConfigURL: URL? = nil, fileManager: FileManager = .default) {
        if let url = uvConfigURL {
            self.uvConfigURL = url
        } else {
            let home = NSHomeDirectory()
            self.uvConfigURL = URL(fileURLWithPath: home + "/.config/uv/uv.toml")
        }
        self.fileManager = fileManager
    }

    public func currentRegistry() throws -> String {
        guard fileManager.fileExists(atPath: uvConfigURL.path) else {
            return Self.defaultRegistry
        }
        let contents: String
        do {
            contents = try String(contentsOf: uvConfigURL, encoding: .utf8)
        } catch {
            throw UvError.configError(error.localizedDescription)
        }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var inIndexBlock = false
        var topLevelIndexURL: String?
        for rawLine in lines {
            let stripped = Self.stripLeadingSpaces(rawLine)
            if stripped.hasPrefix("#") || stripped.hasPrefix(";") { continue }
            if stripped.hasPrefix("[[index]]") {
                inIndexBlock = true
                continue
            }
            if stripped.hasPrefix("[") {
                inIndexBlock = false
                continue
            }
            if inIndexBlock, let value = Self.parseKeyValue(stripped, key: "url") {
                return value
            }
            if !inIndexBlock, topLevelIndexURL == nil,
               let value = Self.parseKeyValue(stripped, key: "index-url") {
                topLevelIndexURL = value
            }
        }
        if let value = topLevelIndexURL {
            return value
        }
        return Self.defaultRegistry
    }

    public func setRegistry(url: String) throws {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw UvError.configError("registry URL must not be empty")
        }

        let parentDir = uvConfigURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            do {
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            } catch {
                throw UvError.configError(error.localizedDescription)
            }
        }

        var existingContents: String?
        if fileManager.fileExists(atPath: uvConfigURL.path) {
            do {
                existingContents = try String(contentsOf: uvConfigURL, encoding: .utf8)
            } catch {
                throw UvError.configError(error.localizedDescription)
            }

            let stamp = Self.timestamp()
            let backupURL = parentDir.appendingPathComponent("uv.toml.\(stamp).bak")
            do {
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: backupURL)
                }
                try fileManager.copyItem(at: uvConfigURL, to: backupURL)
            } catch {
                throw UvError.configError(error.localizedDescription)
            }
        }

        let cleaned = Self.removeIndexBlocks(from: existingContents ?? "")
        var output = cleaned
        if !output.isEmpty && !output.hasSuffix("\n") {
            output.append("\n")
        }
        if !output.isEmpty {
            output.append("\n")
        }
        output.append("[[index]]\n")
        output.append("url = \"\(trimmed)\"\n")

        do {
            try output.write(to: uvConfigURL, atomically: true, encoding: .utf8)
        } catch {
            throw UvError.configError(error.localizedDescription)
        }
    }

    public func presetRegistries() -> [UvRegistryPreset] {
        [
            UvRegistryPreset(
                id: "pypi",
                name: "PyPI Official",
                url: "https://pypi.org/simple"
            ),
            UvRegistryPreset(
                id: "tsinghua",
                name: "Tsinghua TUNA",
                url: "https://pypi.tuna.tsinghua.edu.cn/simple"
            ),
            UvRegistryPreset(
                id: "aliyun",
                name: "Alibaba Cloud",
                url: "https://mirrors.aliyun.com/pypi/simple/"
            ),
            UvRegistryPreset(
                id: "tencent",
                name: "Tencent Cloud",
                url: "https://mirrors.cloud.tencent.com/pypi/simple"
            ),
            UvRegistryPreset(
                id: "ustc",
                name: "USTC",
                url: "https://pypi.mirrors.ustc.edu.cn/simple"
            )
        ]
    }

    private static func removeIndexBlocks(from contents: String) -> String {
        if contents.isEmpty { return "" }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [String] = []
        var inIndexBlock = false
        for rawLine in lines {
            let stripped = Self.stripLeadingSpaces(rawLine)
            if stripped.hasPrefix("[[index]]") {
                inIndexBlock = true
                continue
            }
            if stripped.hasPrefix("[") {
                inIndexBlock = false
                result.append(rawLine)
                continue
            }
            if inIndexBlock {
                continue
            }
            result.append(rawLine)
        }
        while let last = result.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeLast()
        }
        return result.joined(separator: "\n")
    }

    private static func parseKeyValue(_ line: String, key: String) -> String? {
        let lower = line.lowercased()
        guard lower.hasPrefix(key.lowercased()) else { return nil }
        let afterKey = line.dropFirst(key.count)
        var index = afterKey.startIndex
        while index < afterKey.endIndex, afterKey[index] == " " || afterKey[index] == "\t" {
            index = afterKey.index(after: index)
        }
        guard index < afterKey.endIndex, afterKey[index] == "=" else { return nil }
        let rhs = afterKey[afterKey.index(after: index)...]
            .trimmingCharacters(in: .whitespaces)
        guard !rhs.isEmpty else { return nil }
        // Strip surrounding quotes if present.
        if rhs.hasPrefix("\"") && rhs.hasSuffix("\"") && rhs.count >= 2 {
            return String(rhs.dropFirst().dropLast())
        }
        if rhs.hasPrefix("'") && rhs.hasSuffix("'") && rhs.count >= 2 {
            return String(rhs.dropFirst().dropLast())
        }
        // Strip trailing comment.
        if let hashIdx = rhs.firstIndex(of: "#") {
            let head = rhs[..<hashIdx].trimmingCharacters(in: .whitespaces)
            return head.isEmpty ? nil : head
        }
        return rhs
    }

    private static func stripLeadingSpaces(_ line: String) -> String {
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        return String(line[index...])
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
