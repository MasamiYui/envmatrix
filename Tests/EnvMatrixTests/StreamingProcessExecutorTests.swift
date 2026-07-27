import XCTest
@testable import EnvMatrix

final class StreamingProcessExecutorTests: XCTestCase {
    func testStreamPrintfEmitsTwoLines() async throws {
        let executor = DefaultProcessExecutor()
        let collector = LineCollector()

        let result = try await executor.stream(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            args: ["line1\nline2\n"],
            onLine: { line in
                collector.append(line)
            }
        )

        XCTAssertEqual(result.exitCode, 0)
        let lines = collector.snapshot().filter { !$0.hasPrefix("stderr: ") }
        XCTAssertGreaterThanOrEqual(lines.count, 2, "expected at least 2 stdout lines, got: \(lines)")
        XCTAssertTrue(lines.contains("line1"), "missing line1 in: \(lines)")
        XCTAssertTrue(lines.contains("line2"), "missing line2 in: \(lines)")
    }

    func testStreamViaShellScriptAlsoEmitsTwoLines() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let scriptURL = tmpDir.appendingPathComponent("envmatrix_stream_\(UUID().uuidString).sh")
        let scriptBody = "#!/bin/sh\necho line1\necho line2\n"
        try scriptBody.data(using: .utf8)!.write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let executor = DefaultProcessExecutor()
        let collector = LineCollector()

        let result = try await executor.stream(
            executable: URL(fileURLWithPath: "/bin/sh"),
            args: [scriptURL.path],
            onLine: { line in
                collector.append(line)
            }
        )

        XCTAssertEqual(result.exitCode, 0)
        let lines = collector.snapshot().filter { !$0.hasPrefix("stderr: ") }
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertTrue(lines.contains("line1"))
        XCTAssertTrue(lines.contains("line2"))
    }

    func testSpawnCancelTerminatesProcess() async throws {
        let executor = DefaultProcessExecutor()
        let collector = LineCollector()

        let handle = executor.spawn(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            args: ["5"],
            onLine: { line in
                collector.append(line)
            }
        )

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(handle.isRunning, "process should be running before cancel")
        handle.cancel()

        let deadline = Date().addingTimeInterval(3.0)
        while handle.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertFalse(handle.isRunning, "process should not be running after cancel")
    }
}

private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}
