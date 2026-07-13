import XCTest
@testable import EnvMatrix

final class ModelsTests: XCTestCase {
    func testRuntimeKindCount() {
        XCTAssertEqual(RuntimeKind.allCases.count, 11)
    }

    func testBinaryNameMapping() {
        XCTAssertEqual(RuntimeKind.node.binaryName, "node")
        XCTAssertEqual(RuntimeKind.python.binaryName, "python3")
        XCTAssertEqual(RuntimeKind.java.binaryName, "java")
        XCTAssertEqual(RuntimeKind.go.binaryName, "go")
        XCTAssertEqual(RuntimeKind.rust.binaryName, "rustc")
    }

    func testRuntimeVersionID() {
        let v = RuntimeVersion(kind: .node, version: "20.0.0")
        XCTAssertEqual(v.id, "node-20.0.0")
    }
}
