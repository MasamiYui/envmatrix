import XCTest
@testable import EnvMatrix

final class ContainerServiceMockExecutor: ProcessExecutor {
    struct Call {
        let executable: URL
        let args: [String]
        let timeout: TimeInterval?
    }
    var calls: [Call] = []
    var responses: [(ProcessResult)?] = []

    func run(executable: URL, args: [String], timeout: TimeInterval?) async throws -> ProcessResult {
        calls.append(Call(executable: executable, args: args, timeout: timeout))
        let idx = calls.count - 1
        if idx < responses.count {
            if let r = responses[idx] { return r }
            throw ProcessExecutorError.timeout
        }
        return ProcessResult(stdout: "", stderr: "", exitCode: 0)
    }
}

final class ContainerServiceStubShellPathResolver: ShellPathResolver {
    let dirs: [URL]
    init(dirs: [URL]) { self.dirs = dirs }
    func resolvePathDirs() -> [URL] { dirs }
}

enum ContainerServiceFixtures {
    static func makeTempBinDir(binaryName: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-\(binaryName)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bin = root.appendingPathComponent(binaryName)
        let script = "#!/bin/sh\nexit 0\n"
        try script.data(using: .utf8)!.write(to: bin, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        return root
    }
}

final class DockerContainerServiceTests: XCTestCase {
    var tempBinDir: URL!
    var executor: ContainerServiceMockExecutor!
    var service: DefaultDockerContainerService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempBinDir = try ContainerServiceFixtures.makeTempBinDir(binaryName: "docker")
        executor = ContainerServiceMockExecutor()
        service = DefaultDockerContainerService(
            executor: executor,
            shellPathResolver: ContainerServiceStubShellPathResolver(dirs: [tempBinDir]),
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

    func testList_parsesStates() async throws {
        let stdout = """
{"ID":"abc123","Image":"nginx:latest","Command":"nginx -g","State":"running","Status":"Up 5 minutes","Names":"web","Ports":"0.0.0.0:80->80/tcp","CreatedAt":"2024-01-02 03:04:05 +0000 UTC"}
{"ID":"def456","Image":"redis:7","Command":"redis-server","State":"exited","Status":"Exited (0) 1 hour ago","Names":"cache,cache-alt","Ports":"","CreatedAt":"2024-02-03 04:05:06 +0000 UTC"}
{"ID":"ghi789","Image":"postgres:15","Command":"postgres","State":"paused","Status":"Paused","Names":"db","Ports":"5432/tcp","CreatedAt":"2024-03-04 05:06:07 +0000 UTC"}
"""
        executor.responses = [ProcessResult(stdout: stdout, stderr: "", exitCode: 0)]
        let result = try await service.list(all: true)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].state, .running)
        XCTAssertEqual(result[1].state, .exited)
        XCTAssertEqual(result[2].state, .paused)
        XCTAssertEqual(result[1].names, ["cache", "cache-alt"])
        XCTAssertEqual(result[0].portsSummary, "0.0.0.0:80->80/tcp")
        XCTAssertEqual(executor.calls.last?.args, ["ps", "-a", "--format", "{{json .}}"])
    }

    func testLogsTailArgs() async throws {
        executor.responses = [ProcessResult(stdout: "log-output", stderr: "", exitCode: 0)]
        let output = try await service.logs(id: "abc", tail: 150)
        XCTAssertEqual(output, "log-output")
        XCTAssertEqual(executor.calls.last?.args, ["logs", "--tail", "150", "abc"])
    }

    func testInvalidID_throwsInvalidInput() async {
        do {
            try await service.start(id: "bad id")
            XCTFail("Expected invalidInput")
        } catch let error as ContainerContextsError {
            switch error {
            case .invalidInput:
                break
            default:
                XCTFail("Expected invalidInput, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
