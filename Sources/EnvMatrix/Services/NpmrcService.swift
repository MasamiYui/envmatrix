import Foundation

public enum NpmrcError: Error, LocalizedError {
    case fileError(String)
    case writeError(String)

    public var errorDescription: String? {
        switch self {
        case .fileError(let message):
            if message.isEmpty {
                return "Failed to access the .npmrc file."
            }
            return "Failed to access the .npmrc file: \(message)"
        case .writeError(let message):
            if message.isEmpty {
                return "Failed to write the .npmrc file."
            }
            return "Failed to write the .npmrc file: \(message)"
        }
    }
}

public protocol NpmrcService {
    var npmrcURL: URL { get }
    func readRegistry() throws -> String
    func writeRegistry(_ url: String) throws
    func presetMirrors() -> [NodeRegistryMirror]
}

public final class DefaultNpmrcService: NpmrcService {
    private static let npmDefaultRegistry = "https://registry.npmjs.org/"
    private static let backupFilename = ".npmrc.envmatrix.bak"

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

    public func readRegistry() throws -> String {
        guard fileManager.fileExists(atPath: npmrcURL.path) else {
            return Self.npmDefaultRegistry
        }
        let contents: String
        do {
            contents = try String(contentsOf: npmrcURL, encoding: .utf8)
        } catch {
            throw NpmrcError.fileError(error.localizedDescription)
        }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            if let value = Self.parseRegistryLine(line) {
                return value
            }
        }
        return Self.npmDefaultRegistry
    }

    public func writeRegistry(_ url: String) throws {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw NpmrcError.writeError("registry URL must not be empty")
        }

        let parentDir = npmrcURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            do {
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            } catch {
                throw NpmrcError.writeError(error.localizedDescription)
            }
        }

        let backupURL = parentDir.appendingPathComponent(Self.backupFilename)
        if fileManager.fileExists(atPath: npmrcURL.path) {
            if fileManager.fileExists(atPath: backupURL.path) {
                do {
                    try fileManager.removeItem(at: backupURL)
                } catch {
                    throw NpmrcError.writeError(error.localizedDescription)
                }
            }
            do {
                try fileManager.copyItem(at: npmrcURL, to: backupURL)
            } catch {
                throw NpmrcError.writeError(error.localizedDescription)
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
                throw NpmrcError.writeError(error.localizedDescription)
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
            throw NpmrcError.writeError(error.localizedDescription)
        }
    }

    public func presetMirrors() -> [NodeRegistryMirror] {
        [
            NodeRegistryMirror(
                id: "npmmirror",
                name: "npmmirror (Taobao)",
                url: "https://registry.npmmirror.com",
                isPreset: true
            ),
            NodeRegistryMirror(
                id: "tencent",
                name: "Tencent Cloud",
                url: "https://mirrors.cloud.tencent.com/npm/",
                isPreset: true
            ),
            NodeRegistryMirror(
                id: "huawei",
                name: "HuaweiCloud",
                url: "https://mirrors.huaweicloud.com/repository/npm/",
                isPreset: true
            ),
            NodeRegistryMirror(
                id: "npmjs",
                name: "npm Official",
                url: "https://registry.npmjs.org/",
                isPreset: true
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
}
