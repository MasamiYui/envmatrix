import XCTest
@testable import EnvMatrix

final class MCPServiceTests: XCTestCase {
    var tempRoot: URL!
    var configURL: URL!
    var service: DefaultMCPService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        configURL = tempRoot
            .appendingPathComponent("EnvMatrix", isDirectory: true)
            .appendingPathComponent("mcp.json")
        service = DefaultMCPService(configURL: configURL)
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    func testAddThenListReturnsOne() throws {
        let server = MCPServer(
            name: "demo",
            command: "/bin/echo",
            args: ["hello"],
            env: ["KEY": "value"]
        )
        try service.add(server)

        let listed = try service.list()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].name, "demo")
        XCTAssertEqual(listed[0].command, "/bin/echo")
        XCTAssertEqual(listed[0].args, ["hello"])
        XCTAssertEqual(listed[0].env, ["KEY": "value"])
    }

    func testUpdateChangesName() throws {
        var server = MCPServer(name: "before", command: "/bin/echo")
        try service.add(server)

        server = MCPServer(
            id: server.id,
            name: "after",
            command: server.command,
            args: server.args,
            env: server.env
        )
        try service.update(server)

        let listed = try service.list()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].name, "after")
    }

    func testDeleteRemovesEntry() throws {
        let server = MCPServer(name: "demo", command: "/bin/echo")
        try service.add(server)
        try service.delete(server.id)
        XCTAssertTrue(try service.list().isEmpty)
    }

    func testFileIsValidJSON() throws {
        let server = MCPServer(name: "demo", command: "/bin/echo")
        try service.add(server)

        let data = try Data(contentsOf: configURL)
        let obj = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(obj is [String: Any])
        let root = obj as? [String: Any]
        XCTAssertNotNil(root?["servers"] as? [[String: Any]])
    }

    func testListCreatesEmptyFileWhenMissing() throws {
        let listed = try service.list()
        XCTAssertTrue(listed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testUpdateMissingThrows() {
        let ghost = MCPServer(name: "ghost", command: "/bin/echo")
        XCTAssertThrowsError(try service.update(ghost))
    }

    func testDeleteMissingThrows() {
        XCTAssertThrowsError(try service.delete(UUID()))
    }
}
