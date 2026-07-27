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

public final class StreamingHandle: @unchecked Sendable {
    private let process: Process

    init(process: Process) {
        self.process = process
    }

    public func cancel() {
        if process.isRunning {
            process.terminate()
        }
    }

    public var isRunning: Bool {
        process.isRunning
    }
}

public protocol StreamingProcessExecutor: ProcessExecutor {
    func stream(
        executable: URL,
        args: [String],
        onLine: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult

    func spawn(
        executable: URL,
        args: [String],
        onLine: @Sendable @escaping (String) -> Void
    ) -> StreamingHandle
}

private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private var captured = ""
    private let prefix: String
    private let onLine: @Sendable (String) -> Void

    init(prefix: String, onLine: @escaping @Sendable (String) -> Void) {
        self.prefix = prefix
        self.onLine = onLine
    }

    func append(_ chunk: String) {
        lock.lock()
        pending.append(chunk)
        captured.append(chunk)
        var emitted: [String] = []
        while let newlineIndex = pending.firstIndex(of: "\n") {
            let line = String(pending[..<newlineIndex])
            pending.removeSubrange(...newlineIndex)
            emitted.append(line)
        }
        lock.unlock()
        for line in emitted {
            onLine(prefix + line)
        }
    }

    func flush() {
        lock.lock()
        let remaining = pending
        pending = ""
        lock.unlock()
        if !remaining.isEmpty {
            onLine(prefix + remaining)
        }
    }

    var collected: String {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }
}

extension DefaultProcessExecutor: StreamingProcessExecutor {
    public func stream(
        executable: URL,
        args: [String],
        onLine: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = LineBuffer(prefix: "", onLine: onLine)
        let stderrBuffer = LineBuffer(prefix: "stderr: ", onLine: onLine)

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let text = String(data: data, encoding: .utf8) {
                stdoutBuffer.append(text)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let text = String(data: data, encoding: .utf8) {
                stderrBuffer.append(text)
            }
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw ProcessExecutorError.launchFailed(error.localizedDescription)
        }

        await Task.detached(priority: .utility) { [process] in
            process.waitUntilExit()
        }.value

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let tailOut = try? stdoutPipe.fileHandleForReading.readToEnd()
        if let tailOut, let text = String(data: tailOut, encoding: .utf8), !text.isEmpty {
            stdoutBuffer.append(text)
        }
        let tailErr = try? stderrPipe.fileHandleForReading.readToEnd()
        if let tailErr, let text = String(data: tailErr, encoding: .utf8), !text.isEmpty {
            stderrBuffer.append(text)
        }

        stdoutBuffer.flush()
        stderrBuffer.flush()

        return ProcessResult(
            stdout: stdoutBuffer.collected,
            stderr: stderrBuffer.collected,
            exitCode: process.terminationStatus
        )
    }

    public func spawn(
        executable: URL,
        args: [String],
        onLine: @Sendable @escaping (String) -> Void
    ) -> StreamingHandle {
        let process = Process()
        process.executableURL = executable
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = LineBuffer(prefix: "", onLine: onLine)
        let stderrBuffer = LineBuffer(prefix: "stderr: ", onLine: onLine)

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let text = String(data: data, encoding: .utf8) {
                stdoutBuffer.append(text)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let text = String(data: data, encoding: .utf8) {
                stderrBuffer.append(text)
            }
        }

        process.terminationHandler = { _ in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stdoutBuffer.flush()
            stderrBuffer.flush()
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            onLine("stderr: \(error.localizedDescription)")
        }

        return StreamingHandle(process: process)
    }
}
