import Foundation

/// Knows whether `~/.envmatrix/shims` is reachable from the user's terminal,
/// and can write the one-line PATH export into the user's shell rc file.
///
/// "Set Active" only re-points a symlink inside the shims directory. Unless
/// that directory is on PATH the switch is invisible in the terminal, so the
/// UI surfaces this check prominently and offers a one-click fix.
public protocol ShimsPathService {
    /// True when the shims directory appears in the user's login-shell PATH.
    func isShimsOnPath() -> Bool
    /// The rc file that will receive the export line (created if missing).
    func targetRcFile() -> ShellRcFile
    /// The exact line users can paste themselves.
    var exportLine: String { get }
    /// Appends the export line to `targetRcFile()` (idempotent) and returns
    /// the rc file that was written.
    @discardableResult
    func addShimsToShellRc() throws -> ShellRcFile
}

public final class DefaultShimsPathService: ShimsPathService {
    public static let marker = "# Added by EnvMatrix: runtime shims"

    private let shimsDir: URL
    private let pathResolver: ShellPathResolver
    private let shellEnv: ShellEnvService
    private let homeURL: URL
    private let fileManager: FileManager

    public init(
        shimsDir: URL = FileSystem.shimsDir,
        pathResolver: ShellPathResolver = DefaultShellPathResolver(),
        shellEnv: ShellEnvService = DefaultShellEnvService(),
        home: URL = FileSystem.homeURL,
        fileManager: FileManager = .default
    ) {
        self.shimsDir = shimsDir
        self.pathResolver = pathResolver
        self.shellEnv = shellEnv
        self.homeURL = home
        self.fileManager = fileManager
    }

    public var exportLine: String {
        let homePath = homeURL.standardizedFileURL.path
        let shimsPath = shimsDir.standardizedFileURL.path
        if shimsPath.hasPrefix(homePath + "/") {
            let relative = String(shimsPath.dropFirst(homePath.count))
            return "export PATH=\"$HOME\(relative):$PATH\""
        }
        return "export PATH=\"\(shimsPath):$PATH\""
    }

    public func isShimsOnPath() -> Bool {
        let target = shimsDir.standardizedFileURL.resolvingSymlinksInPath().path
        return pathResolver.resolvePathDirs().contains { dir in
            dir.standardizedFileURL.resolvingSymlinksInPath().path == target
        }
    }

    public func targetRcFile() -> ShellRcFile {
        let kind = shellEnv.currentShellKind() ?? .zshrc
        let url = homeURL.appendingPathComponent(kind.defaultRelativePath)
        return ShellRcFile(
            kind: kind,
            url: url,
            exists: fileManager.fileExists(atPath: url.path),
            isCurrentShell: true
        )
    }

    @discardableResult
    public func addShimsToShellRc() throws -> ShellRcFile {
        let file = targetRcFile()
        let existing = file.exists ? (try? shellEnv.read(file)) ?? "" : ""
        if Self.alreadyContainsShims(existing, shimsDir: shimsDir) {
            return file
        }
        var text = existing
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        if !text.isEmpty { text += "\n" }
        text += "\(Self.marker)\n\(exportLine)\n"
        try shellEnv.write(file, text: text)
        DefaultShellPathResolver.invalidateCache()
        return file
    }

    /// True when the rc text already puts the shims directory on PATH,
    /// either via our marker or via a hand-written export.
    static func alreadyContainsShims(_ text: String, shimsDir: URL) -> Bool {
        if text.contains(marker) { return true }
        let needle = "/.envmatrix/shims"
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            if trimmed.contains(needle) && trimmed.contains("PATH") { return true }
            if trimmed.contains(shimsDir.path) && trimmed.contains("PATH") { return true }
        }
        return false
    }
}
