import Foundation

public enum ShellEnvServiceError: Error, LocalizedError {
    case fileNotFound(String)
    case readFailed(String)
    case writeFailed(String)
    case backupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Shell rc file not found: \(path)"
        case .readFailed(let msg):
            return "Failed to read shell rc file: \(msg)"
        case .writeFailed(let msg):
            return "Failed to write shell rc file: \(msg)"
        case .backupFailed(let msg):
            return "Failed to back up shell rc file: \(msg)"
        }
    }
}

public protocol ShellEnvService {
    func availableFiles() -> [ShellRcFile]
    func read(_ file: ShellRcFile) throws -> String
    @discardableResult
    func write(_ file: ShellRcFile, text: String) throws -> URL?
    func currentShellKind() -> ShellRcKind?
}

public final class DefaultShellEnvService: ShellEnvService {
    private let fileManager: FileManager
    private let homeURL: URL
    private let shellPath: String?

    public init(
        fileManager: FileManager = .default,
        home: URL? = nil,
        shellPath: String? = nil
    ) {
        self.fileManager = fileManager
        self.homeURL = home ?? URL(fileURLWithPath: NSHomeDirectory())
        self.shellPath = shellPath ?? ProcessInfo.processInfo.environment["SHELL"]
    }

    public func availableFiles() -> [ShellRcFile] {
        let current = currentShellKind()
        var results: [ShellRcFile] = []
        for kind in ShellRcKind.allCases {
            let url = homeURL.appendingPathComponent(kind.defaultRelativePath)
            let exists = fileManager.fileExists(atPath: url.path)
            guard exists else { continue }
            results.append(
                ShellRcFile(
                    kind: kind,
                    url: url,
                    exists: true,
                    isCurrentShell: current == kind
                )
            )
        }
        return results
    }

    public func read(_ file: ShellRcFile) throws -> String {
        guard fileManager.fileExists(atPath: file.url.path) else {
            throw ShellEnvServiceError.fileNotFound(file.url.path)
        }
        do {
            return try String(contentsOf: file.url, encoding: .utf8)
        } catch {
            throw ShellEnvServiceError.readFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public func write(_ file: ShellRcFile, text: String) throws -> URL? {
        var backupURL: URL?
        let targetURL = file.url
        let targetExists = fileManager.fileExists(atPath: targetURL.path)

        if targetExists {
            let timestamp = Self.timestampString(from: Date())
            let parent = targetURL.deletingLastPathComponent()
            let baseName = "\(targetURL.lastPathComponent).envmatrix.\(timestamp).bak"
            var candidate = parent.appendingPathComponent(baseName)
            var counter = 1
            while fileManager.fileExists(atPath: candidate.path) {
                candidate = parent.appendingPathComponent("\(baseName)-\(counter)")
                counter += 1
            }
            do {
                try fileManager.copyItem(at: targetURL, to: candidate)
                backupURL = candidate
            } catch {
                throw ShellEnvServiceError.backupFailed(error.localizedDescription)
            }
        }

        let parent = targetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            do {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                throw ShellEnvServiceError.writeFailed(error.localizedDescription)
            }
        }

        guard let data = text.data(using: .utf8) else {
            throw ShellEnvServiceError.writeFailed("UTF-8 encoding failed")
        }
        do {
            try data.write(to: targetURL, options: .atomic)
        } catch {
            throw ShellEnvServiceError.writeFailed(error.localizedDescription)
        }

        return backupURL
    }

    public func currentShellKind() -> ShellRcKind? {
        ShellRcKind.from(shellPath: shellPath ?? "")
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
