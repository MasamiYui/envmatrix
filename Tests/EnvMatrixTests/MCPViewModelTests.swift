import XCTest
@testable import EnvMatrix

@MainActor
final class MCPViewModelTests: XCTestCase {
    var tempRoot: URL!
    var configURL: URL!
    var service: DefaultMCPService!
    var vm: MCPViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-mcp-vm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        configURL = tempRoot.appendingPathComponent("mcp.json")
        service = DefaultMCPService(configURL: configURL)
        vm = MCPViewModel(service: service)
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    func testStartAddPreparesEditingServer() {
        vm.startAdd()
        XCTAssertTrue(vm.isPresentingEditor)
        XCTAssertNotNil(vm.editing)
        XCTAssertEqual(vm.editing?.name, "")
        XCTAssertEqual(vm.editing?.command, "")
        XCTAssertTrue(vm.editing?.args.isEmpty ?? false)
        XCTAssertTrue(vm.editing?.env.isEmpty ?? false)
    }

    func testSaveAddsNewServer() throws {
        vm.refresh()
        XCTAssertTrue(vm.servers.isEmpty)

        vm.startAdd()
        let editing = try XCTUnwrap(vm.editing)
        let toSave = MCPServer(
            id: editing.id,
            name: "demo",
            command: "/bin/echo",
            args: ["hi"],
            env: ["K": "V"]
        )
        vm.save(toSave)

        XCTAssertEqual(vm.servers.count, 1)
        XCTAssertEqual(vm.servers.first?.name, "demo")
        XCTAssertFalse(vm.isPresentingEditor)
        XCTAssertNil(vm.editing)
    }

    func testSaveUpdatesExistingServer() throws {
        vm.startAdd()
        let editing = try XCTUnwrap(vm.editing)
        let initial = MCPServer(
            id: editing.id,
            name: "before",
            command: "/bin/echo"
        )
        vm.save(initial)
        XCTAssertEqual(vm.servers.count, 1)

        let updated = MCPServer(
            id: editing.id,
            name: "after",
            command: "/bin/echo",
            args: ["--flag"],
            env: [:]
        )
        vm.save(updated)

        XCTAssertEqual(vm.servers.count, 1)
        XCTAssertEqual(vm.servers.first?.name, "after")
        XCTAssertEqual(vm.servers.first?.args, ["--flag"])
    }

    func testDeleteRemovesServer() throws {
        vm.startAdd()
        let editing = try XCTUnwrap(vm.editing)
        let server = MCPServer(
            id: editing.id,
            name: "demo",
            command: "/bin/echo"
        )
        vm.save(server)
        XCTAssertEqual(vm.servers.count, 1)

        vm.delete(server)

        XCTAssertTrue(vm.servers.isEmpty)
    }
}
