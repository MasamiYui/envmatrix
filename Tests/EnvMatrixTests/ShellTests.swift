import XCTest
@testable import EnvMatrix

final class ShellTests: XCTestCase {
    func testEcho() async throws {
        let result = try await Shell.run("/bin/echo", ["hello"])
        XCTAssertEqual(result.stdout, "hello\n")
        XCTAssertEqual(result.exitCode, 0)
    }
}
