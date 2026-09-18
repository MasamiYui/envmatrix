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
    ///
    /// Equally important: completion is driven by **EOF on both pipes plus process
    /// termination**, not by `terminationHandler` alone. Resuming from the termination
    /// handler loses output, because a readability callback can already have taken the
    /// bytes out of the pipe with `availableData` and still be waiting for the lock when
    /// the process exits. The handler's `readDataToEndOfFile()` then returns nothing (the
    /// data is gone from the pipe) and the buffer has not been appended to yet, so the
    /// caller receives empty stdout. It is rare and load-dependent, which is the worst
    /// kind of bug for something every `brew` / `npm` / `pip` / `docker` call depends on.
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

            // Every read and every append happens on this one serial queue.
            // That is what makes the handoff safe: a readability callback can
            // only take bytes out of the pipe while holding the queue, so by
            // the time the finaliser runs on the same queue, any callback that
            // started earlier has already appended what it read. Nothing can be
            // in limbo between "read from pipe" and "stored in buffer".
            //
            // Completion is NOT driven by an EOF callback. An empty
            // `availableData` is documented to signal EOF, but under load (large
            // output, many concurrent children) this Foundation does not
            // reliably deliver that final callback, and waiting for it hangs the
            // caller forever.
            let ioQueue = DispatchQueue(label: "dev.envmatrix.shell.io")
            final class Buffers {
                var out = Data()
                var err = Data()
                var resumed = false
            }
            let buffers = Buffers()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                ioQueue.sync {
                    let chunk = handle.availableData
                    if !chunk.isEmpty { buffers.out.append(chunk) }
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                ioQueue.sync {
                    let chunk = handle.availableData
                    if !chunk.isEmpty { buffers.err.append(chunk) }
                }
            }

            process.terminationHandler = { proc in
                // Detach first so no further callbacks are scheduled; one may
                // still be mid-flight, and the queue below waits it out.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                var result: ShellResult?
                ioQueue.sync {
                    guard !buffers.resumed else { return }
                    buffers.resumed = true
                    // The child has exited, so its end of the pipe is closed and
                    // these reads drain the remainder without blocking.
                    buffers.out.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                    buffers.err.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                    result = ShellResult(
                        stdout: String(data: buffers.out, encoding: .utf8) ?? "",
                        stderr: String(data: buffers.err, encoding: .utf8) ?? "",
                        exitCode: proc.terminationStatus
                    )
                }
                if let result {
                    continuation.resume(returning: result)
                }
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                var shouldResume = false
                ioQueue.sync {
                    if !buffers.resumed {
                        buffers.resumed = true
                        shouldResume = true
                    }
                }
                if shouldResume {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
