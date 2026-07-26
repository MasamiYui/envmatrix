import Foundation

public enum GemError: Error, LocalizedError {
    case commandNotFound
    case commandFailed(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .commandNotFound:
            return "The `gem` command was not found on PATH."
        case .commandFailed(let message):
            if message.isEmpty { return "The `gem` command failed." }
            return "The `gem` command failed: \(message)"
        case .parseFailed(let message):
            if message.isEmpty { return "Failed to parse `gem` output." }
            return "Failed to parse `gem` output: \(message)"
        }
    }
}

public enum GemConfigError: Error, LocalizedError {
    case fileError(String)
    case writeError(String)

    public var errorDescription: String? {
        switch self {
        case .fileError(let m):
            return m.isEmpty ? "Failed to access the ~/.gemrc file." : "Failed to access the ~/.gemrc file: \(m)"
        case .writeError(let m):
            return m.isEmpty ? "Failed to write the ~/.gemrc file." : "Failed to write the ~/.gemrc file: \(m)"
        }
    }
}

public protocol GemService {
    func isGemAvailable() async -> Bool
    func listGlobalGems() async throws -> [RubyGlobalGem]
    func uninstallGem(_ name: String) async throws
    func cacheStats() async throws -> RubyCacheStats
    func cacheClean() async throws
}

public protocol GemConfigService {
    var gemrcURL: URL { get }
    func readSource() throws -> String
    func writeSource(_ url: String) throws
    func presetMirrors() -> [RubyGemSource]
}

public final class DefaultGemService: GemService {
    private let shellPathResolver: ShellPathResolver
    private let fileManager: FileManager

    public init(shellPathResolver: ShellPathResolver = DefaultShellPathResolver(),
                fileManager: FileManager = .default) {
        self.shellPathResolver = shellPathResolver
        self.fileManager = fileManager
    }

    func findGemBinary() async -> URL? {
        var searchDirs = shellPathResolver.resolvePathDirs()
        let fallbacks = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/local/opt/ruby/bin",
            "/opt/homebrew/opt/ruby/bin",
            "/usr/bin"
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
            let candidate = dir.appendingPathComponent("gem")
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    public func isGemAvailable() async -> Bool { await findGemBinary() != nil }

    public func listGlobalGems() async throws -> [RubyGlobalGem] {
        guard let gem = await findGemBinary() else { throw GemError.commandNotFound }
        let result = try await Shell.run(gem.path, ["list", "--local", "--no-verbose"])
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if stdout.isEmpty && result.exitCode != 0 {
            throw GemError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var gems: [RubyGlobalGem] = []
        for rawLine in stdout.split(separator: "\n") {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let openIdx = line.firstIndex(of: "(") {
                let name = line[..<openIdx].trimmingCharacters(in: .whitespaces)
                let after = line[line.index(after: openIdx)...]
                let closeEnd = after.firstIndex(of: ")") ?? after.endIndex
                let versionsSegment = after[..<closeEnd]
                let firstVersion = versionsSegment
                    .split(separator: ",")
                    .first
                    .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                if !name.isEmpty {
                    gems.append(RubyGlobalGem(name: name, version: firstVersion))
                }
            } else {
                gems.append(RubyGlobalGem(name: line, version: ""))
            }
        }
        gems.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return gems
    }

    public func uninstallGem(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GemError.commandFailed("Gem name must not be empty") }
        guard let gem = await findGemBinary() else { throw GemError.commandNotFound }
        let result = try await Shell.run(gem.path, ["uninstall", trimmed, "-a", "-I", "-x"])
        if result.exitCode != 0 {
            throw GemError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func cacheStats() async throws -> RubyCacheStats {
        let candidates = [
            NSHomeDirectory() + "/.gem/ruby",
            NSHomeDirectory() + "/.gem"
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
            return RubyCacheStats(path: chosenPath, sizeBytes: 0)
        }
        let path = chosenPath
        let size: Int64 = await Task.detached(priority: .utility) { [fileManager] in
            Self.directorySize(at: URL(fileURLWithPath: path), fileManager: fileManager)
        }.value
        return RubyCacheStats(path: path, sizeBytes: size)
    }

    public func cacheClean() async throws {
        guard let gem = await findGemBinary() else { throw GemError.commandNotFound }
        let result = try await Shell.run(gem.path, ["cleanup"])
        if result.exitCode != 0 {
            throw GemError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func directorySize(at url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            if let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize {
                total += Int64(size)
            }
        }
        return total
    }
}

public final class DefaultGemConfigService: GemConfigService {
    private static let gemDefaultSource = "https://rubygems.org/"
    private static let backupFilename = ".gemrc.envmatrix.bak"

    public let gemrcURL: URL
    private let fileManager: FileManager

    public init(gemrcURL: URL? = nil, fileManager: FileManager = .default) {
        if let url = gemrcURL {
            self.gemrcURL = url
        } else {
            self.gemrcURL = URL(fileURLWithPath: NSHomeDirectory() + "/.gemrc")
        }
        self.fileManager = fileManager
    }

    public func readSource() throws -> String {
        guard fileManager.fileExists(atPath: gemrcURL.path) else { return Self.gemDefaultSource }
        let contents: String
        do {
            contents = try String(contentsOf: gemrcURL, encoding: .utf8)
        } catch {
            throw GemConfigError.fileError(error.localizedDescription)
        }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            let stripped = Self.stripLeadingSpaces(line)
            guard stripped.hasPrefix("sources:") else { continue }
            let rhs = stripped.dropFirst("sources:".count).trimmingCharacters(in: .whitespaces)
            if rhs.hasPrefix("[") && rhs.hasSuffix("]") {
                let inner = rhs.dropFirst().dropLast()
                let first = inner.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
                if let f = first, !f.isEmpty {
                    return Self.stripQuotes(f)
                }
            }
        }
        for (i, line) in lines.enumerated() {
            let stripped = Self.stripLeadingSpaces(line)
            if stripped == "sources:" || stripped.hasPrefix("sources:") {
                for j in (i + 1)..<lines.count {
                    let l = lines[j]
                    let s = Self.stripLeadingSpaces(l)
                    if s.hasPrefix("- ") {
                        let value = s.dropFirst(2).trimmingCharacters(in: .whitespaces)
                        return Self.stripQuotes(value)
                    } else if !s.isEmpty && !l.hasPrefix(" ") && !l.hasPrefix("\t") {
                        break
                    }
                }
            }
        }
        return Self.gemDefaultSource
    }

    public func writeSource(_ url: String) throws {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw GemConfigError.writeError("source URL must not be empty")
        }
        let parentDir = gemrcURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            do {
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            } catch {
                throw GemConfigError.writeError(error.localizedDescription)
            }
        }
        let backupURL = parentDir.appendingPathComponent(Self.backupFilename)
        if fileManager.fileExists(atPath: gemrcURL.path) {
            if fileManager.fileExists(atPath: backupURL.path) {
                do { try fileManager.removeItem(at: backupURL) } catch {
                    throw GemConfigError.writeError(error.localizedDescription)
                }
            }
            do { try fileManager.copyItem(at: gemrcURL, to: backupURL) } catch {
                throw GemConfigError.writeError(error.localizedDescription)
            }
        }

        var existingLines: [String] = []
        if fileManager.fileExists(atPath: gemrcURL.path) {
            do {
                let contents = try String(contentsOf: gemrcURL, encoding: .utf8)
                existingLines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                if let last = existingLines.last, last.isEmpty { existingLines.removeLast() }
            } catch {
                throw GemConfigError.writeError(error.localizedDescription)
            }
        }

        var newLines: [String] = []
        var i = 0
        var sourcesReplaced = false
        while i < existingLines.count {
            let line = existingLines[i]
            let stripped = Self.stripLeadingSpaces(line)
            if !sourcesReplaced && (stripped == "sources:" || stripped.hasPrefix("sources:")) {
                newLines.append(":sources:")
                newLines.append("- \(trimmed)")
                sourcesReplaced = true
                i += 1
                while i < existingLines.count {
                    let l = existingLines[i]
                    let s = Self.stripLeadingSpaces(l)
                    if s.hasPrefix("- ") {
                        i += 1
                    } else {
                        break
                    }
                }
            } else {
                newLines.append(line)
                i += 1
            }
        }
        if !sourcesReplaced {
            newLines.append(":sources:")
            newLines.append("- \(trimmed)")
        }

        let output = newLines.joined(separator: "\n") + "\n"
        do {
            try output.write(to: gemrcURL, atomically: true, encoding: .utf8)
        } catch {
            throw GemConfigError.writeError(error.localizedDescription)
        }
    }

    public func presetMirrors() -> [RubyGemSource] {
        [
            RubyGemSource(id: "ruby-china", name: "RubyChina", url: "https://gems.ruby-china.com/", isPreset: true),
            RubyGemSource(id: "tuna", name: "Tsinghua TUNA", url: "https://mirrors.tuna.tsinghua.edu.cn/rubygems/", isPreset: true),
            RubyGemSource(id: "ustc", name: "USTC", url: "https://mirrors.ustc.edu.cn/rubygems/", isPreset: true),
            RubyGemSource(id: "rubygems", name: "RubyGems Official", url: "https://rubygems.org/", isPreset: true)
        ]
    }

    private static func stripLeadingSpaces(_ line: String) -> String {
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        return String(line[index...])
    }

    private static func stripQuotes(_ s: String) -> String {
        var v = s
        if v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2 { v = String(v.dropFirst().dropLast()) }
        else if v.hasPrefix("'") && v.hasSuffix("'") && v.count >= 2 { v = String(v.dropFirst().dropLast()) }
        return v
    }
}
