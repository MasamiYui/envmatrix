import Foundation

/// Resolves runtime-scannable directories from the user's real shell environment.
/// The default implementation launches the user's login shell to obtain the real
/// PATH they see in their terminal — which transparently covers all PATH-based
/// version managers (asdf, mise, rtx, nvm, volta, fnm, Homebrew keg-only, etc.)
/// without needing to hardcode each vendor's directory layout.
public protocol ShellPathResolver {
    /// Returns the ordered, deduplicated list of directories from the user's
    /// interactive shell PATH. May return an empty list if resolution fails
    /// (e.g. shell missing, timed out, no permissions).
    func resolvePathDirs() -> [URL]
}

public final class DefaultShellPathResolver: ShellPathResolver {
    private let fileManager: FileManager
    private let timeout: TimeInterval
    private let cacheLock = NSLock()
    private var cached: [URL]?

    public init(
        fileManager: FileManager = .default,
        timeout: TimeInterval = 1.5
    ) {
        self.fileManager = fileManager
        self.timeout = timeout
    }

    public func resolvePathDirs() -> [URL] {
        cacheLock.lock()
        if let cached = cached {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let resolved = computePathDirs()

        cacheLock.lock()
        cached = resolved
        cacheLock.unlock()
        return resolved
    }

    private func computePathDirs() -> [URL] {
        let raw = readShellPATH() ?? readProcessPATH() ?? ""
        return parsePath(raw)
    }

    private func readShellPATH() -> String? {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard fileManager.fileExists(atPath: shellPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-l", "-i", "-c", "printf '%s' \"$PATH\""]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "PROMPT_COMMAND")
        env["PS1"] = ""
        process.environment = env

        do {
            try process.run()
        } catch {
            return nil
        }

        let timeoutItem = DispatchWorkItem { [weak process] in
            guard let process = process, process.isRunning else { return }
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        process.waitUntilExit()
        timeoutItem.cancel()

        guard process.terminationStatus == 0 else { return nil }
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func readProcessPATH() -> String? {
        ProcessInfo.processInfo.environment["PATH"]
    }

    private func parsePath(_ raw: String) -> [URL] {
        guard !raw.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [URL] = []
        for segment in raw.split(separator: ":", omittingEmptySubsequences: true) {
            let path = String(segment)
            let expanded = (path as NSString).expandingTildeInPath
            if seen.insert(expanded).inserted {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: expanded, isDirectory: &isDir),
                   isDir.boolValue {
                    result.append(URL(fileURLWithPath: expanded))
                }
            }
        }
        return result
    }
}
