import XCTest
@testable import EnvMatrix

// Tests for DefaultPodmanContextService argument construction and rollback logic.
final class PodmanContextServiceTests: XCTestCase {
    var tempBinDir: URL!
    var executor: MockProcessExecutor!
    var service: DefaultPodmanContextService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempBinDir = try DockerTestFixtures.makeTempBinDir(binaryName: "podman")
        executor = MockProcessExecutor()
        service = DefaultPodmanContextService(
            executor: executor,
            shellPathResolver: StubShellPathResolver(dirs: [tempBinDir]),
            fileManager: .default
        )
    }

    override func tearDownWithError() throws {
        if let tempBinDir = tempBinDir,
           FileManager.default.fileExists(atPath: tempBinDir.path) {
            try? FileManager.default.removeItem(at: tempBinDir)
        }
        try super.tearDownWithError()
    }

    private static let listPayload = """
[
  {"Name":"machine","URI":"unix:///run/user/501/podman/podman.sock","Identity":"","Default":true,"ReadWrite":true},
  {"Name":"remote","URI":"ssh://user@host/run/podman/podman.sock","Identity":"/tmp/id","Default":false}
]
"""

    func test_listConnections_parsesJSONArray_defaultBadge() async throws {
        executor.responses = [ProcessResult(stdout: Self.listPayload, stderr: "", exitCode: 0)]
        let result = try await service.listConnections()
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].isDefault)
        XCTAssertEqual(result[0].name, "machine")
        XCTAssertFalse(result[1].isDefault)
        XCTAssertTrue(result[1].isReadWrite)
    }

    func test_removeConnection_exactArgs() async throws {
        executor.responses = [ProcessResult(stdout: "", stderr: "", exitCode: 0)]
        try await service.removeConnection("tmp")
        XCTAssertEqual(executor.calls.count, 1)
        XCTAssertEqual(executor.calls.last?.args, ["system", "connection", "remove", "tmp"])
    }

    func test_addConnection_withDefaultAndIdentity_argOrder() async throws {
        executor.responses = [ProcessResult(stdout: "", stderr: "", exitCode: 0)]
        try await service.addConnection(
            name: "name",
            uri: "unix:///s",
            identity: "/tmp/id",
            makeDefault: true
        )
        let args = executor.calls.last?.args ?? []
        let expectedPrefix: [String] = [
            "system", "connection", "add",
            "--default",
            "--identity", "/tmp/id",
            "name", "unix:///s"
        ]
        XCTAssertEqual(args, expectedPrefix)
    }

    func test_replaceConnection_addFailure_rollsBack() async {
        executor.responses = [
            ProcessResult(stdout: Self.listPayload, stderr: "", exitCode: 0),
            ProcessResult(stdout: "", stderr: "", exitCode: 0),
            ProcessResult(stdout: "", stderr: "boom", exitCode: 1),
            ProcessResult(stdout: "", stderr: "", exitCode: 0)
        ]
        do {
            try await service.replaceConnection(
                oldName: "machine",
                newName: "new",
                uri: "unix:///new",
                identity: nil,
                makeDefault: false
            )
            XCTFail("Expected replaceConnection to throw")
        } catch {
            // expected
        }
        XCTAssertEqual(executor.calls.count, 4)
        let fourth = executor.calls[3].args
        XCTAssertEqual(Array(fourth.prefix(3)), ["system", "connection", "add"])
        XCTAssertTrue(fourth.contains("machine"), "args=\(fourth)")
        XCTAssertTrue(fourth.contains("unix:///run/user/501/podman/podman.sock"), "args=\(fourth)")
    }
}
