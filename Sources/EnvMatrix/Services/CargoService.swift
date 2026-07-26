import Foundation

public enum CargoError: Error, LocalizedError {
    case commandNotFound
    case commandFailed(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandNotFound: return "The `cargo` command was not found on PATH."
        case .commandFailed(let m):
            return m.isEmpty ? "The `cargo` command failed." : "The `cargo` command failed: \(m)"
        case .parseFailed(let m):
            return m.isEmpty ? "Failed to parse `cargo` output." : "Failed to parse `cargo` output: \(m)"
        }
    }
}

public enum CargoConfigError: Error, LocalizedError {
    case fileError(String)
    case writeError(String)

    public var errorDescription: String? {
        switch self {
        case .fileError(let m):
            return m.isEmpty ? "Failed to access ~/.cargo/config.toml." : "Failed to access ~/.cargo/config.toml: \(m)"
        case .writeError(let m):
            return m.isEmpty ? "Failed to write ~/.cargo/config.toml." : "Failed to write ~/.cargo/config.toml: \(m)"
        }
    }
}

public protocol CargoService {
    func isCargoAvailable() async -> Bool
    func listGlobalCrates() async throws -> [RustGlobalCrate]
    func uninstallCrate(_ name: String) async throws
    func cacheStats() async throws -> RustCacheStats
    func cacheClean() async throws
}

public protocol CargoConfigService {
    var configURL: URL { get }
    func readRegistry() throws -> String
    func writeRegistry(_ url: String) throws
    func presetMirrors() -> [RustCrateRegistry]
}

public final class DefaultCargoService: CargoService {
    private let shellPathResolver: ShellPathResolver
    private let fileManager: FileManager

    public init(shellPathResolver: ShellPathResolver = DefaultShellPathResolver(),
                fileManager: FileManager = .default) {
        self.shellPathResolver = shellPathResolver
        self.fileManager = fileManager
    }

    func findCargoBinary() async -> URL? {
        var searchDirs = shellPathResolver.resolvePathDirs()
        let fallbacks = [
            NSHomeDirectory() + "/.cargo/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin"
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
            let candidate = dir.appendingPathComponent("cargo")
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    public func isCargoAvailable() async -> Bool { await findCargoBinary() != nil }

    public func listGlobalCrates() async throws -> [RustGlobalCrate] {
        guard let cargo = await findCargoBinary() else { throw CargoError.commandNotFound }
        let result = try await Shell.run(cargo.path, ["install", "--list"])
        let stdout = result.stdout
        if stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && result.exitCode != 0 {
            throw CargoError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var crates: [RustGlobalCrate] = []
        var currentName = ""
        var currentVersion = ""
        for rawLine in stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.isEmpty { continue }
            if line.first == " " || line.first == "\t" { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(":") {
                let head = trimmed.dropLast()
                let parts = head.split(separator: " ")
                if parts.count >= 2 {
                    if !currentName.isEmpty {
                        crates.append(RustGlobalCrate(name: currentName, version: currentVersion))
                    }
                    currentName = String(parts[0])
                    var v = String(parts[1])
                    if v.hasPrefix("v") { v = String(v.dropFirst()) }
                    currentVersion = v
                }
            }
        }
        if !currentName.isEmpty {
            crates.append(RustGlobalCrate(name: currentName, version: currentVersion))
        }
        crates.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return crates
    }

    public func uninstallCrate(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CargoError.commandFailed("Crate name must not be empty") }
        guard let cargo = await findCargoBinary() else { throw CargoError.commandNotFound }
        let result = try await Shell.run(cargo.path, ["uninstall", trimmed])
        if result.exitCode != 0 {
            throw CargoError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func cacheStats() async throws -> RustCacheStats {
        let path = NSHomeDirectory() + "/.cargo/registry"
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return RustCacheStats(path: path, sizeBytes: 0)
        }
        let size: Int64 = await Task.detached(priority: .utility) { [fileManager] in
            DefaultGemService.directorySize(at: URL(fileURLWithPath: path), fileManager: fileManager)
        }.value
        return RustCacheStats(path: path, sizeBytes: size)
    }

    public func cacheClean() async throws {
        let cacheDir = NSHomeDirectory() + "/.cargo/registry/cache"
        let srcDir = NSHomeDirectory() + "/.cargo/registry/src"
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: cacheDir, isDirectory: &isDir), isDir.boolValue {
            let sub = try fileManager.contentsOfDirectory(atPath: cacheDir)
            for item in sub {
                let p = cacheDir + "/" + item
                try? fileManager.removeItem(atPath: p)
            }
        }
        if fileManager.fileExists(atPath: srcDir, isDirectory: &isDir), isDir.boolValue {
            let sub = try fileManager.contentsOfDirectory(atPath: srcDir)
            for item in sub {
                let p = srcDir + "/" + item
                try? fileManager.removeItem(atPath: p)
            }
        }
    }
}

public final class DefaultCargoConfigService: CargoConfigService {
    private static let cargoDefaultRegistry = "https://github.com/rust-lang/crates.io-index"
    private static let backupFilename = "config.toml.envmatrix.bak"

    public let configURL: URL
    private let fileManager: FileManager

    public init(configURL: URL? = nil, fileManager: FileManager = .default) {
        if let url = configURL {
            self.configURL = url
        } else {
            self.configURL = URL(fileURLWithPath: NSHomeDirectory() + "/.cargo/config.toml")
        }
        self.fileManager = fileManager
    }

    public func readRegistry() throws -> String {
        guard fileManager.fileExists(atPath: configURL.path) else { return Self.cargoDefaultRegistry }
        let contents: String
        do {
            contents = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            throw CargoConfigError.fileError(error.localizedDescription)
        }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var currentSection = ""
        var replaceWithName: String? = nil
        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.hasPrefix("[") && stripped.hasSuffix("]") {
                currentSection = String(stripped.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }
            if currentSection == "source.crates-io" {
                if stripped.hasPrefix("replace-with") {
                    if let idx = stripped.firstIndex(of: "=") {
                        let rhs = stripped[stripped.index(after: idx)...].trimmingCharacters(in: .whitespaces)
                        replaceWithName = Self.unquote(rhs)
                    }
                }
            }
        }
        if let name = replaceWithName {
            let target = "source.\(name)"
            currentSection = ""
            for line in lines {
                let stripped = line.trimmingCharacters(in: .whitespaces)
                if stripped.hasPrefix("[") && stripped.hasSuffix("]") {
                    currentSection = String(stripped.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                    continue
                }
                if currentSection == target && stripped.hasPrefix("registry") {
                    if let idx = stripped.firstIndex(of: "=") {
                        let rhs = stripped[stripped.index(after: idx)...].trimmingCharacters(in: .whitespaces)
                        return Self.unquote(rhs)
                    }
                }
            }
        }
        return Self.cargoDefaultRegistry
    }

    public func writeRegistry(_ url: String) throws {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw CargoConfigError.writeError("registry URL must not be empty")
        }
        let parentDir = configURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            do { try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true) }
            catch { throw CargoConfigError.writeError(error.localizedDescription) }
        }
        let backupURL = parentDir.appendingPathComponent(Self.backupFilename)
        if fileManager.fileExists(atPath: configURL.path) {
            if fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.removeItem(at: backupURL)
            }
            do { try fileManager.copyItem(at: configURL, to: backupURL) }
            catch { throw CargoConfigError.writeError(error.localizedDescription) }
        }

        let mirrorName = "envmatrix-mirror"
        let block = """
        [source.crates-io]
        replace-with = "\(mirrorName)"

        [source.\(mirrorName)]
        registry = "\(trimmed)"
        """

        var existing = ""
        if fileManager.fileExists(atPath: configURL.path) {
            existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        }

        var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let last = lines.last, last.isEmpty { lines.removeLast() }
        var filtered: [String] = []
        var currentSection = ""
        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.hasPrefix("[") && stripped.hasSuffix("]") {
                currentSection = String(stripped.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if currentSection == "source.crates-io" || currentSection.hasPrefix("source.") {
                    continue
                }
                filtered.append(line)
                continue
            }
            if currentSection == "source.crates-io" || currentSection.hasPrefix("source.") {
                continue
            }
            filtered.append(line)
        }
        var output = filtered.joined(separator: "\n")
        if !output.isEmpty && !output.hasSuffix("\n") { output += "\n" }
        if !output.isEmpty { output += "\n" }
        output += block + "\n"

        do {
            try output.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw CargoConfigError.writeError(error.localizedDescription)
        }
    }

    public func presetMirrors() -> [RustCrateRegistry] {
        [
            RustCrateRegistry(id: "ustc-sparse", name: "USTC (sparse)", url: "sparse+https://mirrors.ustc.edu.cn/crates.io-index/", isPreset: true),
            RustCrateRegistry(id: "tuna-sparse", name: "Tsinghua TUNA (sparse)", url: "sparse+https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/", isPreset: true),
            RustCrateRegistry(id: "rsproxy-sparse", name: "rsproxy.cn (sparse)", url: "sparse+https://rsproxy.cn/index/", isPreset: true),
            RustCrateRegistry(id: "crates-io", name: "crates.io Official", url: "https://github.com/rust-lang/crates.io-index", isPreset: true)
        ]
    }

    private static func unquote(_ s: String) -> String {
        var v = s
        if v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2 { v = String(v.dropFirst().dropLast()) }
        else if v.hasPrefix("'") && v.hasSuffix("'") && v.count >= 2 { v = String(v.dropFirst().dropLast()) }
        return v
    }
}
