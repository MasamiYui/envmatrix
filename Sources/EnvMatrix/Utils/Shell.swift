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

            process.terminationHandler = { proc in
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""
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
                continuation.resume(throwing: error)
            }
        }
    }
}
