import XCTest
@testable import EnvMatrix

final class PodmanContainerServiceTests: XCTestCase {
    var tempBinDir: URL!
    var executor: MockProcessExecutor!
    var service: DefaultPodmanContainerService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempBinDir = try DockerTestFixtures.makeTempBinDir(binaryName: "podman")
        executor = MockProcessExecutor()
        service = DefaultPodmanContainerService(
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

    func testList_parsesRunning() async throws {
        let stdout = """
        [
          {
            "Id": "c1",
            "Names": ["web"],
            "Image": "nginx:latest",
            "Command": ["nginx", "-g", "daemon off;"],
            "State": "running",
            "Status": "Up 2 hours",
            "Ports": [],
            "Created": 1700000000
          }
        ]
        """
        executor.responses = [ProcessResult(stdout: stdout, stderr: "", exitCode: 0)]
        let instances = try await service.list(all: false)
        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instances[0].id, "c1")
        XCTAssertEqual(instances[0].image, "nginx:latest")
        XCTAssertEqual(instances[0].state, .running)
        XCTAssertEqual(instances[0].command, "nginx -g daemon off;")
        XCTAssertEqual(instances[0].engine, .podman)
    }

    func testList_allFlagAppendsDashA() async throws {
        executor.responses = [ProcessResult(stdout: "[]", stderr: "", exitCode: 0)]
        _ = try await service.list(all: true)
        XCTAssertEqual(executor.calls.last?.args, ["ps", "-a", "--format", "json"])
    }

    func testList_defaultOmitsDashA() async throws {
        executor.responses = [ProcessResult(stdout: "[]", stderr: "", exitCode: 0)]
        _ = try await service.list(all: false)
        XCTAssertEqual(executor.calls.last?.args, ["ps", "--format", "json"])
    }

    func testNotRunning() async {
        executor.responses = [
            ProcessResult(
                stdout: "",
                stderr: "Cannot connect to Podman socket",
                exitCode: 125
            )
        ]
        do {
            _ = try await service.list(all: false)
            XCTFail("Expected notRunning error")
        } catch let ContainerContextsError.notRunning(engine, _) {
            XCTAssertEqual(engine, .podman)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLogs_tailArgFormat() async throws {
        executor.responses = [ProcessResult(stdout: "hello", stderr: "", exitCode: 0)]
        let output = try await service.logs(id: "c1", tail: 200)
        XCTAssertEqual(output, "hello")
        XCTAssertEqual(executor.calls.last?.args, ["logs", "--tail", "200", "c1"])
    }

    func testInvalidID_throwsInvalidInput() async {
        do {
            try await service.start(id: "bad id")
            XCTFail("Expected invalidInput")
        } catch ContainerContextsError.invalidInput {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
