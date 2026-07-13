import XCTest
@testable import EnvMatrix

final class RuntimeKindTests: XCTestCase {
    func testAllCasesCountIsEleven() {
        XCTAssertEqual(RuntimeKind.allCases.count, 11)
    }

    func testNewRuntimesHaveNonEmptyDisplayName() {
        let newKinds: [RuntimeKind] = [.ruby, .php, .deno, .bun, .dotnet, .erlang]
        for k in newKinds {
            XCTAssertFalse(k.displayName.isEmpty)
            XCTAssertFalse(k.displayName.contains(" ") && k.displayName != ".NET")
            XCTAssertFalse(k.binaryName.isEmpty)
            XCTAssertFalse(k.binaryName.contains(" "))
        }
    }

    func testBinaryNames() {
        XCTAssertEqual(RuntimeKind.ruby.binaryName, "ruby")
        XCTAssertEqual(RuntimeKind.php.binaryName, "php")
        XCTAssertEqual(RuntimeKind.deno.binaryName, "deno")
        XCTAssertEqual(RuntimeKind.bun.binaryName, "bun")
        XCTAssertEqual(RuntimeKind.dotnet.binaryName, "dotnet")
        XCTAssertEqual(RuntimeKind.erlang.binaryName, "erl")
    }
}
