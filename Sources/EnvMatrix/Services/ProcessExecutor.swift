import Foundation

/// Errors thrown by `DefaultProcessExecutor` when a child process cannot complete normally.
public enum ProcessExecutorError: Error, LocalizedError {
    case timeout
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "The subprocess timed out before completing."
        case .launchFailed(let m):
            return m.isEmpty ? "Failed to launch subprocess." : "Failed to launch subprocess: \(m)"
        }
    }
}

/// Result of running an external process: captured stdout/stderr and exit code.
public struct ProcessResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

/// Abstraction over child-process execution to allow injection and testing.
public protocol ProcessExecutor {
    func run(executable: URL, args: [String], timeout: TimeInterval?) async throws -> ProcessResult
}

/// Default `ProcessExecutor` implementation using Foundation's `Process` and `Pipe`.
public final class DefaultProcessExecutor: ProcessExecutor {
    public init() {}

    public func run(executable: URL, args: [String], timeout: TimeInterval?) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ProcessExecutorError.launchFailed(error.localizedDescription)
        }

        let timedOutBox = TimedOutBox()

        if let timeout = timeout {
            let sleepTask = Task { [weak process] in
                let nanos = UInt64(max(0, timeout) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled { return }
                guard let process = process, process.isRunning else { return }
                timedOutBox.set()
                process.terminate()
            }

            await Task.detached(priority: .utility) { [process] in
                process.waitUntilExit()
            }.value

            sleepTask.cancel()
        } else {
            await Task.detached(priority: .utility) { [process] in
                process.waitUntilExit()
            }.value
        }

        let outData = Self.readAll(from: stdoutPipe.fileHandleForReading)
        let errData = Self.readAll(from: stderrPipe.fileHandleForReading)

        if timedOutBox.value {
            throw ProcessExecutorError.timeout
        }

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        return ProcessResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }

    private static func readAll(from handle: FileHandle) -> Data {
        if #available(macOS 10.15.4, *) {
            do {
                return try handle.readToEnd() ?? Data()
            } catch {
                return Data()
            }
        } else {
            return handle.readDataToEndOfFile()
        }
    }
}

private final class TimedOutBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func set() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}
