import XCTest
@testable import EnvMatrix

final class ShellTests: XCTestCase {
    func testEcho() async throws {
        let result = try await Shell.run("/bin/echo", ["hello"])
        XCTAssertEqual(result.stdout, "hello\n")
        XCTAssertEqual(result.exitCode, 0)
    }

    /// Regression guard for output being dropped. Completion used to be driven
    /// by `terminationHandler` alone, so a readability callback that had already
    /// taken the bytes out of the pipe but not yet appended them lost the race
    /// and the caller saw empty stdout. Twenty concurrent runs with distinct
    /// payloads make that interleaving likely and pin every result to its own
    /// invocation.
    func testConcurrentRunsEachGetTheirOwnOutput() async throws {
        let count = 20
        let results = await withTaskGroup(of: (Int, String)?.self) { group -> [(Int, String)] in
            for i in 0..<count {
                group.addTask {
                    guard let r = try? await Shell.run("/bin/echo", ["payload-\(i)"]) else { return nil }
                    return (i, r.stdout)
                }
            }
            var collected: [(Int, String)] = []
            for await value in group {
                if let value { collected.append(value) }
            }
            return collected
        }

        XCTAssertEqual(results.count, count, "every run should return a result")
        for (i, stdout) in results {
            XCTAssertEqual(stdout, "payload-\(i)\n", "run \(i) got the wrong or empty output")
        }
    }

    /// The pipes must be drained while the child runs. A child writing more than
    /// the ~64 KB pipe buffer blocks in `write()` if nobody reads, and the whole
    /// call hangs. `seq 1 200000` emits well over 1 MB.
    func testLargeOutputIsNeitherTruncatedNorDeadlocked() async throws {
        let result = try await Shell.run("/usr/bin/seq", ["1", "200000"])
        XCTAssertEqual(result.exitCode, 0)
        let lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 200_000, "output was truncated")
        XCTAssertEqual(lines.first, "1")
        XCTAssertEqual(lines.last, "200000")
    }

    func testStderrAndNonZeroExitAreCaptured() async throws {
        // `ls` on a missing path writes to stderr and exits non-zero.
        let result = try await Shell.run("/bin/ls", ["/nonexistent-envmatrix-path-xyz"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.isEmpty, "nothing should reach stdout")
        XCTAssertFalse(result.stderr.isEmpty, "stderr should be captured")
    }

    func testMissingBinaryThrows() async {
        do {
            _ = try await Shell.run("/nonexistent-envmatrix-binary-xyz", [])
            XCTFail("expected a launch failure")
        } catch {
            // Expected: Process.run() throws when the executable does not exist.
        }
    }
}
