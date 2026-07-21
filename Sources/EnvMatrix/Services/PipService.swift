import Foundation

public enum PipError: Error, LocalizedError {
    case commandNotFound
    case commandFailed(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandNotFound:
            return "The `pip3` command was not found on PATH."
        case .commandFailed(let message):
            if message.isEmpty {
                return "The `pip3` command failed."
            }
            return "The `pip3` command failed: \(message)"
        case .parseFailed(let message):
            if message.isEmpty {
                return "Failed to parse `pip3` output."
            }
            return "Failed to parse `pip3` output: \(message)"
        }
    }
}

public enum PipConfError: Error, LocalizedError {
    case fileError(String)
    case writeError(String)

    public var errorDescription: String? {
        switch self {
        case .fileError(let message):
            if message.isEmpty {
                return "Failed to access the pip.conf file."
            }
            return "Failed to access the pip.conf file: \(message)"
        case .writeError(let message):
            if message.isEmpty {
                return "Failed to write the pip.conf file."
            }
            return "Failed to write the pip.conf file: \(message)"
        }
    }
}

public protocol PipService {
    func isPipAvailable() async -> Bool
    func listUserPackages() async throws -> [PythonGlobalPackage]
    func uninstall(_ name: String) async throws
    func cacheStats() async throws -> PythonCacheStats
    func cachePurge() async throws
}

public protocol PipConfService {
    var pipConfURL: URL { get }
    func readIndexURL() throws -> String
    func writeIndexURL(_ url: String) throws
    func presetMirrors() -> [PythonIndexMirror]
}

public final class DefaultPipService: PipService {
    private let shellPathResolver: ShellPathResolver
    private let fileManager: FileManager

    public init(
        shellPathResolver: ShellPathResolver = DefaultShellPathResolver(),
        fileManager: FileManager = .default
    ) {
        self.shellPathResolver = shellPathResolver
        self.fileManager = fileManager
    }

    func findPipBinary() async -> URL? {
        var searchDirs = shellPathResolver.resolvePathDirs()
        let fallbacks = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/local/opt/python/libexec/bin",
            "/Library/Frameworks/Python.framework/Versions/Current/bin"
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

        let candidates = ["pip3", "pip"]
        for dir in searchDirs {
            for name in candidates {
                let candidate = dir.appendingPathComponent(name)
                if fileManager.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    public func isPipAvailable() async -> Bool {
        await findPipBinary() != nil
    }

    public func listUserPackages() async throws -> [PythonGlobalPackage] {
        guard let pip = await findPipBinary() else {
            throw PipError.commandNotFound
        }
        let result = try await Shell.run(pip.path, ["list", "--user", "--format=json"])
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if stdout.isEmpty && result.exitCode != 0 {
            throw PipError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        guard let data = stdout.data(using: .utf8) else {
            throw PipError.parseFailed("stdout is not valid UTF-8")
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw PipError.parseFailed(error.localizedDescription)
        }

        guard let array = jsonObject as? [[String: Any]] else {
            throw PipError.parseFailed("root is not a JSON array")
        }

        var packages: [PythonGlobalPackage] = []
        for entry in array {
            guard let name = entry["name"] as? String,
                  let version = entry["version"] as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            let location = entry["location"] as? String
            packages.append(PythonGlobalPackage(name: name, version: version, location: location))
        }

        packages.sort { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return packages
    }

    public func uninstall(_ name: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw PipError.commandFailed("Package name must not be empty")
        }
        guard let pip = await findPipBinary() else {
            throw PipError.commandNotFound
        }
        let result = try await Shell.run(pip.path, ["uninstall", "-y", trimmedName])
        if result.exitCode != 0 {
            throw PipError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    public func cacheStats() async throws -> PythonCacheStats {
        let path = NSHomeDirectory() + "/Library/Caches/pip"
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return PythonCacheStats(path: path, sizeBytes: 0)
        }
        let total = directorySize(at: URL(fileURLWithPath: path))
        return PythonCacheStats(path: path, sizeBytes: total)
    }

    public func cachePurge() async throws {
        guard let pip = await findPipBinary() else {
            throw PipError.commandNotFound
        }
        let result = try await Shell.run(pip.path, ["cache", "purge"])
        if result.exitCode != 0 {
            throw PipError.commandFailed(
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

public final class DefaultPipConfService: PipConfService {
    private static let pipDefaultIndex = "https://pypi.org/simple"
    private static let backupFilename = "pip.conf.envmatrix.bak"

    public let pipConfURL: URL
    private let fileManager: FileManager

    public init(pipConfURL: URL? = nil, fileManager: FileManager = .default) {
        if let url = pipConfURL {
            self.pipConfURL = url
        } else {
            let home = NSHomeDirectory()
            self.pipConfURL = URL(fileURLWithPath: home + "/.config/pip/pip.conf")
        }
        self.fileManager = fileManager
    }

    public func readIndexURL() throws -> String {
        guard fileManager.fileExists(atPath: pipConfURL.path) else {
            return Self.pipDefaultIndex
        }
        let contents: String
        do {
            contents = try String(contentsOf: pipConfURL, encoding: .utf8)
        } catch {
            throw PipConfError.fileError(error.localizedDescription)
        }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            if let value = Self.parseIndexLine(line) {
                return value
            }
        }
        return Self.pipDefaultIndex
    }

    public func writeIndexURL(_ url: String) throws {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw PipConfError.writeError("index URL must not be empty")
        }

        let parentDir = pipConfURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            do {
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            } catch {
                throw PipConfError.writeError(error.localizedDescription)
            }
        }

        let backupURL = parentDir.appendingPathComponent(Self.backupFilename)
        if fileManager.fileExists(atPath: pipConfURL.path) {
            if fileManager.fileExists(atPath: backupURL.path) {
                do {
                    try fileManager.removeItem(at: backupURL)
                } catch {
                    throw PipConfError.writeError(error.localizedDescription)
                }
            }
            do {
                try fileManager.copyItem(at: pipConfURL, to: backupURL)
            } catch {
                throw PipConfError.writeError(error.localizedDescription)
            }
        }

        var existingLines: [String] = []
        if fileManager.fileExists(atPath: pipConfURL.path) {
            do {
                let contents = try String(contentsOf: pipConfURL, encoding: .utf8)
                existingLines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                if let last = existingLines.last, last.isEmpty {
                    existingLines.removeLast()
                }
            } catch {
                throw PipConfError.writeError(error.localizedDescription)
            }
        }

        var newLines: [String] = []
        var hasGlobalSection = false
        var indexHandled = false
        var inGlobalSection = false

        for line in existingLines {
            let stripped = Self.stripLeadingSpaces(line)
            if stripped.hasPrefix("[") && stripped.contains("]") {
                let sectionName = Self.sectionName(stripped)
                if inGlobalSection && !indexHandled {
                    newLines.append("index-url = \(trimmed)")
                    indexHandled = true
                }
                inGlobalSection = (sectionName == "global")
                if inGlobalSection { hasGlobalSection = true }
                newLines.append(line)
                continue
            }
            if inGlobalSection, Self.isIndexAssignmentLine(stripped) {
                if !indexHandled {
                    newLines.append("index-url = \(trimmed)")
                    indexHandled = true
                }
                continue
            }
            newLines.append(line)
        }

        if inGlobalSection && !indexHandled {
            newLines.append("index-url = \(trimmed)")
            indexHandled = true
        }

        if !hasGlobalSection {
            if !newLines.isEmpty {
                newLines.append("")
            }
            newLines.append("[global]")
            newLines.append("index-url = \(trimmed)")
        }

        let output = newLines.joined(separator: "\n") + "\n"
        do {
            try output.write(to: pipConfURL, atomically: true, encoding: .utf8)
        } catch {
            throw PipConfError.writeError(error.localizedDescription)
        }
    }

    public func presetMirrors() -> [PythonIndexMirror] {
        [
            PythonIndexMirror(
                id: "tsinghua",
                name: "Tsinghua TUNA",
                url: "https://pypi.tuna.tsinghua.edu.cn/simple",
                isPreset: true
            ),
            PythonIndexMirror(
                id: "aliyun",
                name: "Alibaba Cloud",
                url: "https://mirrors.aliyun.com/pypi/simple/",
                isPreset: true
            ),
            PythonIndexMirror(
                id: "tencent",
                name: "Tencent Cloud",
                url: "https://mirrors.cloud.tencent.com/pypi/simple",
                isPreset: true
            ),
            PythonIndexMirror(
                id: "ustc",
                name: "USTC",
                url: "https://pypi.mirrors.ustc.edu.cn/simple",
                isPreset: true
            ),
            PythonIndexMirror(
                id: "pypi",
                name: "PyPI Official",
                url: "https://pypi.org/simple",
                isPreset: true
            )
        ]
    }

    private static func parseIndexLine(_ line: String) -> String? {
        let stripped = Self.stripLeadingSpaces(line)
        if stripped.hasPrefix(";") || stripped.hasPrefix("#") {
            return nil
        }
        guard isIndexAssignmentLine(stripped) else { return nil }
        let key: String
        if stripped.lowercased().hasPrefix("index-url") {
            key = "index-url"
        } else if stripped.lowercased().hasPrefix("index_url") {
            key = "index_url"
        } else {
            return nil
        }
        let afterKey = stripped.dropFirst(key.count)
        var index = afterKey.startIndex
        while index < afterKey.endIndex, afterKey[index] == " " || afterKey[index] == "\t" {
            index = afterKey.index(after: index)
        }
        guard index < afterKey.endIndex else { return nil }
        guard afterKey[index] == "=" || afterKey[index] == ":" else { return nil }
        let rhs = afterKey[afterKey.index(after: index)...]
        let value = rhs.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func isIndexAssignmentLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        guard lower.hasPrefix("index-url") || lower.hasPrefix("index_url") else { return false }
        let key = lower.hasPrefix("index-url") ? "index-url" : "index_url"
        let afterKey = lower.dropFirst(key.count)
        var index = afterKey.startIndex
        while index < afterKey.endIndex, afterKey[index] == " " || afterKey[index] == "\t" {
            index = afterKey.index(after: index)
        }
        guard index < afterKey.endIndex else { return false }
        return afterKey[index] == "=" || afterKey[index] == ":"
    }

    private static func sectionName(_ line: String) -> String {
        guard let start = line.firstIndex(of: "["),
              let end = line.firstIndex(of: "]"),
              start < end else { return "" }
        return String(line[line.index(after: start)..<end])
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    private static func stripLeadingSpaces(_ line: String) -> String {
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        return String(line[index...])
    }
}
