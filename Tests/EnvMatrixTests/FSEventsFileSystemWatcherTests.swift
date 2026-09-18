import XCTest
@testable import EnvMatrix

final class FSEventsFileSystemWatcherTests: XCTestCase {
    actor Counter {
        private(set) var callCount: Int = 0
        private(set) var totalChanges: Int = 0

        func record(_ count: Int) {
            callCount += 1
            totalChanges += count
        }
    }

    private func makeTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        return tempDir
    }

    func testDebouncesRapidChanges() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["CI"] != nil,
            "flaky on CI"
        )

        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let counter = Counter()
        let expectation = XCTestExpectation(description: "onChange called")
        expectation.assertForOverFulfill = false

        let watcher = FSEventsFileSystemWatcher()
        let handle = watcher.watch(
            paths: [tempDir.path],
            latency: 0.1,
            debounceInterval: 0.3,
            onChange: { changes in
                Task {
                    await counter.record(changes.count)
                    expectation.fulfill()
                }
            }
        )
        defer { handle.invalidate() }

        Thread.sleep(forTimeInterval: 0.2)

        for i in 0..<5 {
            let fileURL = tempDir.appendingPathComponent("file_\(i).txt")
            try Data("hello".utf8).write(to: fileURL)
        }

        wait(for: [expectation], timeout: 2.0)
        try? await Task.sleep(nanoseconds: 500_000_000)

        let callCount = await counter.callCount
        let totalChanges = await counter.totalChanges
        XCTAssertEqual(callCount, 1, "expected debounced single callback, got \(callCount)")
        XCTAssertGreaterThanOrEqual(totalChanges, 1)
    }

    func testInvalidateStopsEvents() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["CI"] != nil,
            "flaky on CI"
        )

        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let counter = Counter()
        let watcher = FSEventsFileSystemWatcher()
        let handle = watcher.watch(
            paths: [tempDir.path],
            latency: 0.1,
            debounceInterval: 0.3,
            onChange: { changes in
                Task {
                    await counter.record(changes.count)
                }
            }
        )

        Thread.sleep(forTimeInterval: 0.2)
        handle.invalidate()

        let fileURL = tempDir.appendingPathComponent("post_invalidate.txt")
        try Data("bye".utf8).write(to: fileURL)

        Thread.sleep(forTimeInterval: 1.5)

        let callCount = await counter.callCount
        XCTAssertEqual(callCount, 0, "expected no callbacks after invalidate, got \(callCount)")
    }

    func testMissingPathDoesNotCrash() {
        let watcher = FSEventsFileSystemWatcher()
        let handle = watcher.watch(
            paths: ["/nonexistent/path/xyz"],
            latency: 0.1,
            debounceInterval: 0.3,
            onChange: { _ in }
        )
        XCTAssertNotNil(handle)
        handle.invalidate()
    }
}
