import XCTest
@testable import EnvMatrix

final class IntegrationTests: XCTestCase {
    var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-integration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    // MARK: - Runtime lifecycle

    func testRuntimeLifecycle() throws {
        let service = DefaultRuntimeService(root: tempRoot, providers: nil, systemDetector: nil)

        let binDir = tempRoot
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("node", isDirectory: true)
            .appendingPathComponent("20.10.0", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let nodeBin = binDir.appendingPathComponent("node")
        XCTAssertTrue(
            FileManager.default.createFile(atPath: nodeBin.path, contents: Data("#!/bin/sh\n".utf8))
        )

        let installed = try service.listInstalled(kind: .node)
        XCTAssertTrue(installed.contains { $0.version == "20.10.0" })

        let rv = RuntimeVersion(kind: .node, version: "20.10.0")
        try service.activate(version: rv)

        XCTAssertEqual(service.currentActive(kind: .node), "20.10.0")

        let shim = tempRoot
            .appendingPathComponent("shims", isDirectory: true)
            .appendingPathComponent("node")
        let shimAttrs = try FileManager.default.attributesOfItem(atPath: shim.path)
        let type = shimAttrs[.type] as? FileAttributeType
        XCTAssertTrue(
            type == .typeSymbolicLink || type == .typeRegular,
            "shim should exist as symlink or file, got: \(String(describing: type))"
        )

        try service.uninstall(version: rv)

        let versionDir = tempRoot
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("node", isDirectory: true)
            .appendingPathComponent("20.10.0", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: versionDir.path))
        XCTAssertNil(service.currentActive(kind: .node))
    }

    // MARK: - Skills toggle

    func testSkillsToggleIntegration() throws {
        let coderDir = tempRoot.appendingPathComponent("coder", isDirectory: true)
        let writerDir = tempRoot.appendingPathComponent("writer.disabled", isDirectory: true)
        try FileManager.default.createDirectory(at: coderDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: writerDir, withIntermediateDirectories: true)

        let service = DefaultSkillsService(searchPaths: [tempRoot])

        let listed = try service.list()
        XCTAssertEqual(listed.count, 2)

        let coder = try XCTUnwrap(listed.first { $0.name == "coder" })
        let disabledCoder = try service.disable(coder)
        XCTAssertEqual(disabledCoder.path.lastPathComponent, "coder.disabled")
        XCTAssertFalse(FileManager.default.fileExists(atPath: coderDir.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempRoot.appendingPathComponent("coder.disabled").path
            )
        )

        let writer = try XCTUnwrap(listed.first { $0.name == "writer" })
        let enabledWriter = try service.enable(writer)
        XCTAssertEqual(enabledWriter.path.lastPathComponent, "writer")
        XCTAssertFalse(FileManager.default.fileExists(atPath: writerDir.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempRoot.appendingPathComponent("writer").path
            )
        )

        try service.delete(disabledCoder)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempRoot.appendingPathComponent("coder.disabled").path
            )
        )
    }

    // MARK: - MCP CRUD

    func testMCPCRUDIntegration() throws {
        let configURL = tempRoot.appendingPathComponent("mcp.json")
        let service = DefaultMCPService(configURL: configURL)

        let server = MCPServer(
            name: "s1",
            command: "/bin/echo",
            args: ["hi"],
            env: ["K": "V"]
        )
        try service.add(server)
        XCTAssertEqual(try service.list().count, 1)

        let renamed = MCPServer(
            id: server.id,
            name: "s2",
            command: server.command,
            args: server.args,
            env: server.env
        )
        try service.update(renamed)
        XCTAssertEqual(try service.list().first?.name, "s2")

        try service.delete(server.id)
        XCTAssertTrue(try service.list().isEmpty)

        let data = try Data(contentsOf: configURL)
        let obj = try JSONSerialization.jsonObject(with: data)
        let root = try XCTUnwrap(obj as? [String: Any])
        XCTAssertNotNil(root["servers"] as? [[String: Any]])
    }

    // MARK: - CLI config masking

    func testCLIConfigMasking() throws {
        let settingsURL = tempRoot.appendingPathComponent("settings.json")
        let seed: [String: Any] = ["apiKey": "sk-abcdefghij1234"]
        let data = try JSONSerialization.data(withJSONObject: seed, options: [.prettyPrinted])
        try data.write(to: settingsURL, options: .atomic)

        let service = DefaultCLIConfigService(configPaths: [
            CLIConfigPath(id: "claude-code", name: "Claude Code", url: settingsURL)
        ])
        let configs = service.list()
        XCTAssertEqual(configs.count, 1)
        let masked = try XCTUnwrap(configs[0].apiKeyMasked)
        XCTAssertTrue(masked.contains("****"))
        XCTAssertFalse(masked.contains("efghij"))
    }
}
