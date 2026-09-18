import XCTest
@testable import EnvMatrix

final class MockRunner: ShellRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount: Int = 0
    private var _inflight: Int = 0
    private var _maxInflight: Int = 0
    let delay: TimeInterval

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _callCount
    }

    var maxInflight: Int {
        lock.lock()
        defer { lock.unlock() }
        return _maxInflight
    }

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func run(command: String, arguments: [String], environment: [String: String]?) async throws -> ProcessResult {
        lock.lock()
        _callCount += 1
        _inflight += 1
        if _inflight > _maxInflight { _maxInflight = _inflight }
        let currentCount = _callCount
        lock.unlock()

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        lock.lock()
        _inflight -= 1
        lock.unlock()

        return ProcessResult(stdout: "\(currentCount)", stderr: "", exitCode: 0)
    }
}

final class DefaultProcessPoolTests: XCTestCase {
    func testConcurrencyLimit() async throws {
        let mock = MockRunner(delay: 0.2)
        let pool = DefaultProcessPool(maxConcurrent: 2, queueLimit: 100, runner: mock)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    _ = try? await pool.run(command: "/bin/echo", arguments: [], environment: nil, dedupeKey: nil)
                }
            }
            await group.waitForAll()
        }

        XCTAssertLessThanOrEqual(mock.maxInflight, 2)
    }

    func testDedupeShareResults() async throws {
        let mock = MockRunner(delay: 0.1)
        let pool = DefaultProcessPool(maxConcurrent: 4, queueLimit: 100, runner: mock)

        async let r1 = pool.run(command: "/bin/echo", arguments: [], environment: nil, dedupeKey: "k1")
        async let r2 = pool.run(command: "/bin/echo", arguments: [], environment: nil, dedupeKey: "k1")

        let (result1, result2) = try await (r1, r2)
        XCTAssertEqual(mock.callCount, 1)
        XCTAssertEqual(result1.stdout, result2.stdout)
    }

    func testDifferentDedupeKeysNotMerged() async throws {
        let mock = MockRunner(delay: 0.05)
        let pool = DefaultProcessPool(maxConcurrent: 4, queueLimit: 100, runner: mock)

        async let r1 = pool.run(command: "/bin/echo", arguments: [], environment: nil, dedupeKey: "a")
        async let r2 = pool.run(command: "/bin/echo", arguments: [], environment: nil, dedupeKey: "b")

        _ = try await (r1, r2)
        XCTAssertEqual(mock.callCount, 2)
    }

    func testNilDedupeKeyDoesNotMerge() async throws {
        let mock = MockRunner(delay: 0.05)
        let pool = DefaultProcessPool(maxConcurrent: 4, queueLimit: 100, runner: mock)

        async let r1 = pool.run(command: "/bin/echo", arguments: [], environment: nil, dedupeKey: nil)
        async let r2 = pool.run(command: "/bin/echo", arguments: [], environment: nil, dedupeKey: nil)

        _ = try await (r1, r2)
        XCTAssertEqual(mock.callCount, 2)
    }

    func testQueueFullThrows() async throws {
        let mock = MockRunner(delay: 0.5)
        let pool = DefaultProcessPool(maxConcurrent: 1, queueLimit: 2, runner: mock)

        let t1 = Task.detached {
            try await pool.run(command: "/bin/echo", arguments: [], environment: nil, dedupeKey: nil)
        }
        let t2 = Task.detached {
            try await pool.run(command: "/bin/echo", arguments: [], environment: nil, dedupeKey: nil)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        let t3 = Task.detached {
            try await pool.run(command: "/bin/echo", arguments: [], environment: nil, dedupeKey: nil)
        }

        var results: [Result<ProcessResult, Error>] = []
        for t in [t1, t2, t3] {
            do {
                let r = try await t.value
                results.append(.success(r))
            } catch {
                results.append(.failure(error))
            }
        }

        let failures = results.compactMap { r -> Error? in
            if case .failure(let e) = r { return e }
            return nil
        }
        XCTAssertEqual(failures.count, 1)
        guard let firstFailure = failures.first else {
            XCTFail("expected a queueFull failure")
            return
        }
        if case ProcessPoolError.queueFull = firstFailure {
            XCTAssertTrue(true)
        } else {
            XCTFail("expected queueFull, got \(firstFailure)")
        }
    }

    func testCancelAllCancelsInflight() async throws {
        let mock = MockRunner(delay: 2.0)
        let pool = DefaultProcessPool(maxConcurrent: 4, queueLimit: 100, runner: mock)

        let t1 = Task.detached { try await pool.run(command: "/bin/echo", arguments: [], environment: nil, dedupeKey: nil) }
        let t2 = Task.detached { try await pool.run(command: "/bin/echo", arguments: [], environment: nil, dedupeKey: nil) }
        let t3 = Task.detached { try await pool.run(command: "/bin/echo", arguments: [], environment: nil, dedupeKey: nil) }

        try await Task.sleep(nanoseconds: 100_000_000)
        pool.cancelAll()

        var cancelledCount = 0
        for t in [t1, t2, t3] {
            do {
                _ = try await t.value
            } catch is CancellationError {
                cancelledCount += 1
            } catch {
                if error is CancellationError {
                    cancelledCount += 1
                }
            }
        }
        XCTAssertEqual(cancelledCount, 3)
    }
}
