import Foundation

public enum PnpmError: Error, LocalizedError {
    case commandNotFound
    case commandFailed(String)
    case parseFailed(String)
    case configError(String)

    public var errorDescription: String? {
        switch self {
        case .commandNotFound:
            return "The `pnpm` command was not found on PATH."
        case .commandFailed(let message):
            if message.isEmpty {
                return "The `pnpm` command failed."
            }
            return "The `pnpm` command failed: \(message)"
        case .parseFailed(let message):
            if message.isEmpty {
                return "Failed to parse `pnpm` output."
            }
            return "Failed to parse `pnpm` output: \(message)"
        case .configError(let message):
            if message.isEmpty {
                return "Failed to access the .npmrc file."
            }
            return "Failed to access the .npmrc file: \(message)"
        }
    }
}

public protocol PnpmService {
    func isAvailable() async -> Bool
    func listGlobalPackages() async throws -> [PnpmGlobalPackage]
    func uninstallGlobal(_ name: String) async throws
    func storeStats() async throws -> PnpmStoreStats
    func storePrune() async throws
}

public protocol PnpmConfigService {
    var npmrcURL: URL { get }
    func currentRegistry() throws -> String
    func setRegistry(url: String) throws
    func presetRegistries() -> [PnpmRegistryPreset]
}

public final class DefaultPnpmService: PnpmService {
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
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/share/pnpm"),
            (NSHomeDirectory() as NSString).appendingPathComponent("Library/pnpm")
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
            let candidate = dir.appendingPathComponent("pnpm")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    public func isAvailable() async -> Bool {
        await findBinary() != nil
    }

    public func listGlobalPackages() async throws -> [PnpmGlobalPackage] {
        guard let pnpm = await findBinary() else {
            throw PnpmError.commandNotFound
        }
        let result = try await Shell.run(pnpm.path, ["ls", "-g", "--depth=0", "--json"])
        let stdout = result.stdout
        let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedStdout.isEmpty && result.exitCode != 0 {
            throw PnpmError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return try Self.parseGlobalPackages(json: trimmedStdout)
    }

    internal static func parseGlobalPackages(json: String) throws -> [PnpmGlobalPackage] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        guard let data = trimmed.data(using: .utf8) else {
            throw PnpmError.parseFailed("stdout is not valid UTF-8")
        }
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw PnpmError.parseFailed(error.localizedDescription)
        }

        var rootObjects: [[String: Any]] = []
        if let array = jsonObject as? [[String: Any]] {
            rootObjects = array
        } else if let object = jsonObject as? [String: Any] {
            rootObjects = [object]
        } else {
            throw PnpmError.parseFailed("root is neither an object nor an array")
        }

        var packages: [PnpmGlobalPackage] = []
        for root in rootObjects {
            guard let dependencies = root["dependencies"] as? [String: Any] else { continue }
            for (name, rawEntry) in dependencies {
                guard let entry = rawEntry as? [String: Any] else { continue }
                guard let version = entry["version"] as? String,
                      !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                let path = entry["path"] as? String
                packages.append(PnpmGlobalPackage(name: name, version: version, path: path))
            }
        }

        packages.sort { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return packages
    }

    public func uninstallGlobal(_ name: String) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw PnpmError.commandFailed("Package name must not be empty")
        }
        guard let pnpm = await findBinary() else {
            throw PnpmError.commandNotFound
        }
        let result = try await Shell.run(pnpm.path, ["uninstall", "-g", trimmedName])
        if result.exitCode != 0 {
            throw PnpmError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    public func storeStats() async throws -> PnpmStoreStats {
        guard let pnpm = await findBinary() else {
            throw PnpmError.commandNotFound
        }
        let result = try await Shell.run(pnpm.path, ["store", "path"])
        if result.exitCode != 0 {
            throw PnpmError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let path = Self.parseStorePath(result.stdout)
        guard !path.isEmpty else {
            throw PnpmError.parseFailed("store path is empty")
        }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return PnpmStoreStats(path: path, sizeBytes: 0)
        }
        let total = directorySize(at: URL(fileURLWithPath: path))
        return PnpmStoreStats(path: path, sizeBytes: total)
    }

    public func storePrune() async throws {
        guard let pnpm = await findBinary() else {
            throw PnpmError.commandNotFound
        }
        let result = try await Shell.run(pnpm.path, ["store", "prune"])
        if result.exitCode != 0 {
            throw PnpmError.commandFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    internal static func parseStorePath(_ raw: String) -> String {
        let stripped = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return stripped
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

public final class DefaultPnpmConfigService: PnpmConfigService {
    private static let defaultRegistry = "https://registry.npmjs.org/"

    public let npmrcURL: URL
    private let fileManager: FileManager

    public init(npmrcURL: URL? = nil, fileManager: FileManager = .default) {
        if let url = npmrcURL {
            self.npmrcURL = url
        } else {
            let home = NSHomeDirectory()
            self.npmrcURL = URL(fileURLWithPath: home + "/.npmrc")
        }
        self.fileManager = fileManager
    }

    public func currentRegistry() throws -> String {
        guard fileManager.fileExists(atPath: npmrcURL.path) else {
            return Self.defaultRegistry
        }
        let contents: String
        do {
            contents = try String(contentsOf: npmrcURL, encoding: .utf8)
        } catch {
            throw PnpmError.configError(error.localizedDescription)
        }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            if let value = Self.parseRegistryLine(line) {
                return value
            }
        }
        return Self.defaultRegistry
    }

    public func setRegistry(url: String) throws {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw PnpmError.configError("registry URL must not be empty")
        }

        let parentDir = npmrcURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            do {
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            } catch {
                throw PnpmError.configError(error.localizedDescription)
            }
        }

        var existingLines: [String] = []
        if fileManager.fileExists(atPath: npmrcURL.path) {
            do {
                let contents = try String(contentsOf: npmrcURL, encoding: .utf8)
                existingLines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                if let last = existingLines.last, last.isEmpty {
                    existingLines.removeLast()
                }
            } catch {
                throw PnpmError.configError(error.localizedDescription)
            }

            let stamp = Self.timestamp()
            let backupURL = parentDir.appendingPathComponent(".npmrc.\(stamp).pnpm.bak")
            do {
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: backupURL)
                }
                try fileManager.copyItem(at: npmrcURL, to: backupURL)
            } catch {
                throw PnpmError.configError(error.localizedDescription)
            }
        }

        var newLines: [String] = []
        var found = false
        for line in existingLines {
            if Self.isRegistryAssignmentLine(line) {
                newLines.append("registry=\(trimmed)")
                found = true
            } else {
                newLines.append(line)
            }
        }
        if !found {
            newLines.append("registry=\(trimmed)")
        }

        let output = newLines.joined(separator: "\n") + "\n"
        do {
            try output.write(to: npmrcURL, atomically: true, encoding: .utf8)
        } catch {
            throw PnpmError.configError(error.localizedDescription)
        }
    }

    public func presetRegistries() -> [PnpmRegistryPreset] {
        [
            PnpmRegistryPreset(
                id: "npmmirror",
                name: "npmmirror (Taobao)",
                url: "https://registry.npmmirror.com"
            ),
            PnpmRegistryPreset(
                id: "tencent",
                name: "Tencent Cloud",
                url: "https://mirrors.cloud.tencent.com/npm/"
            ),
            PnpmRegistryPreset(
                id: "huawei",
                name: "HuaweiCloud",
                url: "https://mirrors.huaweicloud.com/repository/npm/"
            ),
            PnpmRegistryPreset(
                id: "npmjs",
                name: "npm Official",
                url: "https://registry.npmjs.org/"
            )
        ]
    }

    private static func parseRegistryLine(_ line: String) -> String? {
        let stripped = Self.stripLeadingSpaces(line)
        if stripped.hasPrefix(";") || stripped.hasPrefix("#") {
            return nil
        }
        guard stripped.hasPrefix("registry") else {
            return nil
        }
        let afterKey = stripped.dropFirst("registry".count)
        var index = afterKey.startIndex
        while index < afterKey.endIndex, afterKey[index] == " " || afterKey[index] == "\t" {
            index = afterKey.index(after: index)
        }
        guard index < afterKey.endIndex else { return nil }
        let separator = afterKey[index]
        guard separator == "=" || separator == " " else { return nil }
        let rhs = afterKey[afterKey.index(after: index)...]
        let value = rhs.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func isRegistryAssignmentLine(_ line: String) -> Bool {
        let stripped = Self.stripLeadingSpaces(line)
        if stripped.hasPrefix(";") || stripped.hasPrefix("#") {
            return false
        }
        guard stripped.hasPrefix("registry") else { return false }
        let afterKey = stripped.dropFirst("registry".count)
        var index = afterKey.startIndex
        while index < afterKey.endIndex, afterKey[index] == " " || afterKey[index] == "\t" {
            index = afterKey.index(after: index)
        }
        guard index < afterKey.endIndex else { return false }
        return afterKey[index] == "="
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
