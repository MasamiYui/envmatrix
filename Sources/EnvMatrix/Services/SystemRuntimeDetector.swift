import Foundation

public protocol SystemRuntimeDetector {
    func detect(kind: RuntimeKind) -> [RuntimeVersion]
}

public final class DefaultSystemRuntimeDetector: SystemRuntimeDetector {
    private let fileManager: FileManager
    private let home: URL
    private let envmatrixRoot: URL

    public init(
        fileManager: FileManager = .default,
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        envmatrixRoot: URL = FileSystem.envmatrixRoot
    ) {
        self.fileManager = fileManager
        self.home = home
        self.envmatrixRoot = envmatrixRoot
    }

    // MARK: - Detect

    public func detect(kind: RuntimeKind) -> [RuntimeVersion] {
        let binaryName = kind.binaryName
        let searchDirs = candidateBinDirs(for: kind)
        let versionArgs = versionArgs(for: kind)
        let managedPrefix = envmatrixRoot
            .appendingPathComponent("versions", isDirectory: true)
            .path

        var seenVersions = Set<String>()
        var seenResolvedPaths = Set<String>()
        var results: [RuntimeVersion] = []

        for dir in searchDirs {
            let candidate = dir.appendingPathComponent(binaryName)
            guard isExecutableFile(at: candidate) else { continue }

            let resolvedPath = resolveSymlink(at: candidate).path
            if resolvedPath.hasPrefix(managedPrefix) { continue }
            if seenResolvedPaths.contains(resolvedPath) { continue }

            guard let raw = runVersionCommand(candidate.path, args: versionArgs),
                  let parsed = parseVersion(raw, kind: kind) else {
                continue
            }

            if seenVersions.contains(parsed) { continue }
            seenVersions.insert(parsed)
            seenResolvedPaths.insert(resolvedPath)

            // installPath = parent of bin (i.e. remove /bin/<binary>)
            let installPath = dir.deletingLastPathComponent()

            results.append(
                RuntimeVersion(
                    kind: kind,
                    version: parsed,
                    installPath: installPath,
                    isSystem: true
                )
            )
        }

        return results
    }

    // MARK: - Candidate directories

    private func candidateBinDirs(for kind: RuntimeKind) -> [URL] {
        var dirs: [URL] = []

        // Common system bin dirs
        for p in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
            dirs.append(URL(fileURLWithPath: p))
        }

        // asdf shims (all kinds)
        dirs.append(home.appendingPathComponent(".asdf/shims"))

        // Cargo (rust)
        dirs.append(home.appendingPathComponent(".cargo/bin"))

        // Kind-specific globs
        switch kind {
        case .node:
            dirs.append(contentsOf: expandGlob("\(home.path)/.nvm/versions/node/*/bin"))
        case .java:
            dirs.append(contentsOf: expandGlob("\(home.path)/.jenv/versions/*/bin"))
            dirs.append(contentsOf: expandGlob("\(home.path)/.sdkman/candidates/java/*/bin"))
            dirs.append(
                contentsOf: expandGlob(
                    "\(home.path)/Library/Java/JavaVirtualMachines/*/Contents/Home/bin"
                )
            )
            dirs.append(
                contentsOf: expandGlob(
                    "/Library/Java/JavaVirtualMachines/*/Contents/Home/bin"
                )
            )
        case .go:
            dirs.append(contentsOf: expandGlob("\(home.path)/.goenv/versions/*/bin"))
        case .python:
            dirs.append(contentsOf: expandGlob("\(home.path)/.pyenv/versions/*/bin"))
        case .rust:
            break
        case .ruby:
            break
        case .php:
            break
        case .deno:
            break
        case .bun:
            break
        case .dotnet:
            break
        case .erlang:
            break
        }

        // Dedupe preserving order
        var seen = Set<String>()
        var unique: [URL] = []
        for d in dirs {
            let p = d.path
            if !seen.contains(p) {
                seen.insert(p)
                unique.append(d)
            }
        }
        return unique
    }

    // MARK: - Glob expansion

    /// Very small manual glob supporting only "*" segments (no "**" or "?").
    /// Splits pattern on "/" and enumerates directories one level per "*".
    func expandGlob(_ pattern: String) -> [URL] {
        let parts = pattern.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var currents: [URL]
        // Handle absolute vs relative
        if pattern.hasPrefix("/") {
            currents = [URL(fileURLWithPath: "/")]
        } else {
            currents = [URL(fileURLWithPath: fileManager.currentDirectoryPath)]
        }

        for part in parts where !part.isEmpty {
            var next: [URL] = []
            if part == "*" {
                for base in currents {
                    guard let children = try? fileManager.contentsOfDirectory(
                        at: base,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    for child in children {
                        var isDir: ObjCBool = false
                        if fileManager.fileExists(atPath: child.path, isDirectory: &isDir),
                           isDir.boolValue {
                            next.append(child)
                        }
                    }
                }
            } else {
                for base in currents {
                    next.append(base.appendingPathComponent(part))
                }
            }
            currents = next
        }
        // Filter to existing directories
        return currents.filter { url in
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    // MARK: - Executable check / symlink resolve

    private func isExecutableFile(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir),
              !isDir.boolValue else {
            return false
        }
        return fileManager.isExecutableFile(atPath: url.path)
    }

    private func resolveSymlink(at url: URL) -> URL {
        let resolved = url.resolvingSymlinksInPath()
        return resolved.standardizedFileURL
    }

    // MARK: - Version args & parsing

    private func versionArgs(for kind: RuntimeKind) -> [String] {
        switch kind {
        case .node: return ["--version"]
        case .python: return ["--version"]
        case .java: return ["-version"]
        case .go: return ["version"]
        case .rust: return ["--version"]
        case .ruby: return ["--version"]
        case .php: return ["--version"]
        case .deno: return ["--version"]
        case .bun: return ["--version"]
        case .dotnet: return ["--version"]
        case .erlang: return ["--version"]
        }
    }

    /// Parses raw version output text into a semantic version string.
    /// Made `internal` so it can be exercised in tests.
    func parseVersion(_ raw: String, kind: RuntimeKind) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch kind {
        case .node:
            // "v20.10.0"
            if trimmed.hasPrefix("v") {
                return String(trimmed.dropFirst())
            }
            return trimmed
        case .python:
            // "Python 3.11.7"
            return firstMatch(in: trimmed, pattern: #"(\d+(?:\.\d+){1,2})"#)
        case .java:
            // openjdk version "17.0.9" ... OR java version "21" ...
            // take substring inside first "..."
            return firstMatch(in: trimmed, pattern: #"\"([^\"]+)\""#, group: 1)
        case .go:
            // "go version go1.22.1 darwin/arm64"
            return firstMatch(in: trimmed, pattern: #"go(\d+(?:\.\d+){1,2})"#, group: 1)
        case .rust:
            // "rustc 1.75.0 (...)"
            return firstMatch(in: trimmed, pattern: #"rustc\s+(\d+(?:\.\d+){1,2})"#, group: 1)
        case .ruby:
            // "ruby 3.3.0p0 (2023-12-25 revision xxx) [arm64-darwin23]"
            return firstMatch(in: trimmed, pattern: #"ruby\s+(\d+\.\d+\.\d+)"#, group: 1)
        case .php:
            // "PHP 8.3.0 (cli) (built: ...)"
            return firstMatch(in: trimmed, pattern: #"PHP\s+(\d+\.\d+\.\d+)"#, group: 1)
        case .deno:
            // "deno 1.40.0 (release, aarch64-apple-darwin)"
            return firstMatch(in: trimmed, pattern: #"deno\s+(\d+\.\d+\.\d+)"#, group: 1)
        case .bun:
            // "1.0.20"
            return firstMatch(in: trimmed, pattern: #"^(\d+\.\d+\.\d+)"#, group: 1)
        case .dotnet:
            // "8.0.100"
            return firstMatch(in: trimmed, pattern: #"^(\d+\.\d+\.\d+)"#, group: 1)
        case .erlang:
            // "Erlang (SMP,ASYNC_THREADS) (BEAM) emulator version 14.2.1"
            if let m = firstMatch(
                in: trimmed,
                pattern: #"emulator version\s+(\d+(?:\.\d+){1,2})"#,
                group: 1
            ) {
                return m
            }
            return firstMatch(in: trimmed, pattern: #"(\d+(?:\.\d+){1,2})"#, group: 1)
        }
    }

    private func firstMatch(in text: String, pattern: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        guard group < match.numberOfRanges else { return nil }
        let r = match.range(at: group)
        guard let swiftRange = Range(r, in: text) else { return nil }
        return String(text[swiftRange])
    }

    // MARK: - Synchronous process runner

    /// Runs `path args` synchronously with a 2-second timeout guard.
    /// Returns combined stdout+stderr text, or nil on failure/timeout.
    func runVersionCommand(_ path: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        // Timeout guard: kill after 2 seconds if still running.
        let timeoutItem = DispatchWorkItem { [weak process] in
            guard let process = process, process.isRunning else { return }
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0, execute: timeoutItem)

        process.waitUntilExit()
        timeoutItem.cancel()

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        let combined = out + err
        if combined.isEmpty && process.terminationStatus != 0 {
            return nil
        }
        return combined
    }
}
