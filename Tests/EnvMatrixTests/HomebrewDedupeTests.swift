import XCTest
@testable import EnvMatrix

/// A `ShellRunner` that returns pre-canned JSON responses based on the first
/// argument of the brew invocation, tracks the total number of underlying
/// process executions, and sleeps briefly to give concurrent callers a chance
/// to dedupe inside `DefaultProcessPool`.
final class MockShellRunner: ShellRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _totalCalls: Int = 0
    private var _callsByFirstArg: [String: Int] = [:]
    let delay: TimeInterval

    var totalCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return _totalCalls
    }

    func callCount(forFirstArg arg: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return _callsByFirstArg[arg] ?? 0
    }

    init(delay: TimeInterval = 0.05) {
        self.delay = delay
    }

    func run(command: String, arguments: [String], environment: [String: String]?) async throws -> ProcessResult {
        let first = arguments.first ?? ""
        lock.lock()
        _totalCalls += 1
        _callsByFirstArg[first, default: 0] += 1
        lock.unlock()

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        let stdout: String
        switch first {
        case "info":
            stdout = "{\"formulae\":[],\"casks\":[]}"
        case "outdated":
            stdout = "{\"formulae\":[],\"casks\":[]}"
        case "--version":
            stdout = "Homebrew 4.0.0\n"
        default:
            stdout = "{\"formulae\":[],\"casks\":[]}"
        }
        return ProcessResult(stdout: stdout, stderr: "", exitCode: 0)
    }
}

final class HomebrewDedupeTests: XCTestCase {
    func testConcurrentInventoryDedupes() async throws {
        let runner = MockShellRunner(delay: 0.2)
        let pool = DefaultProcessPool(maxConcurrent: 4, runner: runner)
        let service = DefaultHomebrewService(brewPath: "/tmp/fake-brew", processPool: pool)

        let t1 = Task.detached { try await service.inventory(forceRefresh: false) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let t2 = Task.detached { try await service.inventory(forceRefresh: false) }
        _ = try await (t1.value, t2.value)

        XCTAssertEqual(runner.totalCalls, 3, "concurrent inventory should dedupe to 3 underlying calls, got \(runner.totalCalls)")
        XCTAssertEqual(runner.callCount(forFirstArg: "info"), 1)
        XCTAssertEqual(runner.callCount(forFirstArg: "outdated"), 1)
        XCTAssertEqual(runner.callCount(forFirstArg: "--version"), 1)
    }

    func testForceRefreshBypassesDedupe() async throws {
        let runner = MockShellRunner(delay: 0.05)
        let pool = DefaultProcessPool(maxConcurrent: 4, runner: runner)
        let service = DefaultHomebrewService(brewPath: "/tmp/fake-brew", processPool: pool)

        async let a: BrewInventory = service.inventory(forceRefresh: true)
        async let b: BrewInventory = service.inventory(forceRefresh: true)
        _ = try await (a, b)

        XCTAssertEqual(runner.totalCalls, 6, "forceRefresh should bypass dedupe, expected 6 calls, got \(runner.totalCalls)")
        XCTAssertEqual(runner.callCount(forFirstArg: "info"), 2)
        XCTAssertEqual(runner.callCount(forFirstArg: "outdated"), 2)
        XCTAssertEqual(runner.callCount(forFirstArg: "--version"), 2)
    }
}
