import Foundation

public struct ShellResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public enum Shell {
    /// Run an external binary and return its collected stdout / stderr / exit code.
    ///
    /// IMPORTANT: This implementation drains both pipes with `readabilityHandler`
    /// while the child is running. Reading only in `terminationHandler` is a well-known
    /// Foundation trap — if the child writes more than the pipe buffer (typically 64 KB
    /// on macOS), it blocks on `write()` and the termination handler never fires,
    /// hanging the caller forever. `brew info --installed --json=v2` emits ~340 KB
    /// on a typical developer machine and reliably deadlocked the previous version.
    public static func run(
        _ launchPath: String,
        _ args: [String],
        env: [String: String]? = nil
    ) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ShellResult, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = args
            if let env = env {
                process.environment = env
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Serialise mutations to the byte accumulators; readabilityHandler
            // callbacks are invoked on a private queue and can interleave.
            let bufferLock = NSLock()
            var outBuffer = Data()
            var errBuffer = Data()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { return }
                bufferLock.lock()
                outBuffer.append(chunk)
                bufferLock.unlock()
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { return }
                bufferLock.lock()
                errBuffer.append(chunk)
                bufferLock.unlock()
            }

            process.terminationHandler = { proc in
                // Stop reading — any remaining bytes in the pipe are still
                // drained by the final availableData reads below.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let tailOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let tailErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                bufferLock.lock()
                outBuffer.append(tailOut)
                errBuffer.append(tailErr)
                let out = String(data: outBuffer, encoding: .utf8) ?? ""
                let err = String(data: errBuffer, encoding: .utf8) ?? ""
                bufferLock.unlock()

                continuation.resume(
                    returning: ShellResult(
                        stdout: out,
                        stderr: err,
                        exitCode: proc.terminationStatus
                    )
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
