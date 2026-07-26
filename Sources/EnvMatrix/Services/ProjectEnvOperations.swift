import Foundation
import AppKit

/// Destructive / long-running operations on a `ProjectEnvironment`.
///
/// Every deletion goes through `FileManager.trashItem(_:resultingItemURL:)` so
/// the user can recover from mistakes via Finder → Undo / restore-from-Trash.
/// We never call `rm -rf` — even a well-tested app can pick a wrong URL from
/// a race, and the difference between "recoverable" and "unrecoverable" is
/// disproportionate to the tiny cost of using Trash.
public final class ProjectEnvOperations {

    private let shellResolver: ShellPathResolver

    public init(shellResolver: ShellPathResolver = DefaultShellPathResolver()) {
        self.shellResolver = shellResolver
    }

    // MARK: - Delete

    /// Move `env.url` to the user's Trash. Throws `ProjectEnvError.deleteFailed`
    /// if the OS refuses (e.g. permission denied, target is on a read-only
    /// volume).
    public func moveToTrash(_ env: ProjectEnvironment) throws {
        do {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: env.url, resultingItemURL: &resulting)
        } catch {
            throw ProjectEnvError.deleteFailed(env.url, underlying: error.localizedDescription)
        }
    }

    // MARK: - Reinstall (node_modules only)

    /// Delete then reinstall a `node_modules` folder using its detected
    /// package manager. Emits stdout/stderr lines through `onOutput` so the
    /// UI can render a live log drawer.
    ///
    /// Preconditions enforced:
    ///   - `env.kind == .nodeModules`
    ///   - The parent project root still exists.
    ///   - A usable package manager is either detected or falls back to `npm`.
    @discardableResult
    public func reinstallNodeModules(
        _ env: ProjectEnvironment,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> ShellResult {
        guard env.kind == .nodeModules else {
            throw ProjectEnvError.reinstallUnsupported(
                reason: "reinstall is only supported for node_modules"
            )
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: env.projectRoot.path) else {
            throw ProjectEnvError.reinstallUnsupported(
                reason: "project root no longer exists: \(env.projectRoot.path)"
            )
        }

        // 1. Move the existing node_modules to Trash (safer than deleting).
        try moveToTrash(env)
        onOutput("[envmatrix] moved \(env.url.path) to Trash\n")

        // 2. Resolve the package manager executable via the user's shell PATH.
        let pm = env.packageManager ?? .npm
        let toolName = pm == .unknown ? "npm" : pm.rawValue
        guard let toolURL = locate(tool: toolName) else {
            throw ProjectEnvError.reinstallUnsupported(
                reason: "\(toolName) not found in PATH — install it or switch to another package manager."
            )
        }
        onOutput("[envmatrix] using \(toolURL.path) \(pm.installArgs.joined(separator: " "))\n")

        // 3. Spawn the install, streaming output.
        return try await runStreaming(
            executable: toolURL,
            args: pm.installArgs,
            cwd: env.projectRoot,
            onOutput: onOutput
        )
    }

    // MARK: - Reveal / open terminal

    /// Reveal the environment directory in Finder.
    public func revealInFinder(_ env: ProjectEnvironment) {
        NSWorkspace.shared.activateFileViewerSelecting([env.url])
    }

    /// Reveal the project root in Finder.
    public func revealProjectInFinder(_ env: ProjectEnvironment) {
        NSWorkspace.shared.activateFileViewerSelecting([env.projectRoot])
    }

    /// Open the project root in the user's default Terminal application via
    /// `open -a Terminal <path>`. We use `open` because it handles Terminal /
    /// iTerm / any AppleScript-driven terminal without us needing to know
    /// which is installed.
    public func openInTerminal(_ env: ProjectEnvironment) throws {
        let openURL = URL(fileURLWithPath: "/usr/bin/open")
        let process = Process()
        process.executableURL = openURL
        process.arguments = ["-a", "Terminal", env.projectRoot.path]
        try process.run()
    }

    // MARK: - Internals

    /// Find an executable by walking the user's login-shell PATH plus a few
    /// well-known fallbacks. Returns `nil` if not found.
    private func locate(tool: String) -> URL? {
        var dirs = shellResolver.resolvePathDirs()
        // Always try Homebrew / system locations even if the shell resolver
        // returned nothing (e.g. in a sandboxed test).
        for extra in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
            let url = URL(fileURLWithPath: extra, isDirectory: true)
            if !dirs.contains(url) { dirs.append(url) }
        }
        for dir in dirs {
            let candidate = dir.appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Run a subprocess and stream stdout/stderr line-by-line through
    /// `onOutput`. Mirrors the pipe-drainage pattern in `Shell.run` — do NOT
    /// wait for termination before reading, or large outputs will deadlock.
    private func runStreaming(
        executable: URL,
        args: [String],
        cwd: URL,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ShellResult, Error>) in
            let process = Process()
            process.executableURL = executable
            process.arguments = args
            process.currentDirectoryURL = cwd
            // Preserve the user's environment so tools like pnpm, corepack,
            // node-gyp find their expected dependencies (Python, Xcode CLI,
            // registry auth, etc.).
            process.environment = ProcessInfo.processInfo.environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let lock = NSLock()
            var outBuffer = Data()
            var errBuffer = Data()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { return }
                lock.lock(); outBuffer.append(chunk); lock.unlock()
                if let text = String(data: chunk, encoding: .utf8) {
                    onOutput(text)
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { return }
                lock.lock(); errBuffer.append(chunk); lock.unlock()
                if let text = String(data: chunk, encoding: .utf8) {
                    onOutput(text)
                }
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let tailOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let tailErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                lock.lock()
                outBuffer.append(tailOut)
                errBuffer.append(tailErr)
                let outStr = String(data: outBuffer, encoding: .utf8) ?? ""
                let errStr = String(data: errBuffer, encoding: .utf8) ?? ""
                lock.unlock()

                continuation.resume(
                    returning: ShellResult(stdout: outStr, stderr: errStr, exitCode: proc.terminationStatus)
                )
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
