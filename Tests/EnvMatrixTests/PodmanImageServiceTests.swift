import XCTest
@testable import EnvMatrix

final class MockPodmanStreamingExecutor: StreamingProcessExecutor, @unchecked Sendable {
    struct Call {
        let executable: URL
        let args: [String]
    }
    var calls: [Call] = []
    var responses: [ProcessResult] = []

    func run(executable: URL, args: [String], timeout: TimeInterval?) async throws -> ProcessResult {
        calls.append(Call(executable: executable, args: args))
        let idx = calls.count - 1
        if idx < responses.count { return responses[idx] }
        return ProcessResult(stdout: "", stderr: "", exitCode: 0)
    }

    func stream(
        executable: URL,
        args: [String],
        onLine: @Sendable @escaping (String) -> Void
    ) async throws -> ProcessResult {
        calls.append(Call(executable: executable, args: args))
        let idx = calls.count - 1
        if idx < responses.count { return responses[idx] }
        return ProcessResult(stdout: "", stderr: "", exitCode: 0)
    }

    func spawn(
        executable: URL,
        args: [String],
        onLine: @Sendable @escaping (String) -> Void
    ) -> StreamingHandle {
        calls.append(Call(executable: executable, args: args))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        return StreamingHandle(process: process)
    }
}

final class PodmanImageServiceTests: XCTestCase {
    var tempBinDir: URL!
    var executor: MockPodmanStreamingExecutor!
    var service: DefaultPodmanImageService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempBinDir = try DockerTestFixtures.makeTempBinDir(binaryName: "podman")
        executor = MockPodmanStreamingExecutor()
        service = DefaultPodmanImageService(
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

    func testList_parsesJSONArray() async throws {
        let stdout = """
        [
          {"Id":"sha256:abc","Names":["docker.io/library/alpine:3.19"],"Size":7000000,"Created":1700000000,"Digest":"sha256:dig"}
        ]
        """
        executor.responses = [ProcessResult(stdout: stdout, stderr: "", exitCode: 0)]
        let images = try await service.list()
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].repository, "docker.io/library/alpine")
        XCTAssertEqual(images[0].tag, "3.19")
        XCTAssertEqual(images[0].sizeBytes, 7_000_000)
        XCTAssertEqual(images[0].engine, .podman)
    }

    func testList_defaultsToLatestWhenNoTag() async throws {
        let stdout = """
        [
          {"Id":"sha256:xyz","Names":["localhost/foo"],"Size":100,"Created":1700000000}
        ]
        """
        executor.responses = [ProcessResult(stdout: stdout, stderr: "", exitCode: 0)]
        let images = try await service.list()
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].repository, "localhost/foo")
        XCTAssertEqual(images[0].tag, "latest")
    }

    func testNotRunning_returnsNotRunningError() async {
        executor.responses = [
            ProcessResult(
                stdout: "",
                stderr: "Cannot connect to Podman. Please verify your connection.",
                exitCode: 125
            )
        ]
        do {
            _ = try await service.list()
            XCTFail("Expected notRunning error")
        } catch let ContainerContextsError.notRunning(engine, stderr) {
            XCTAssertEqual(engine, .podman)
            XCTAssertTrue(stderr.contains("Cannot connect to Podman"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPruneArgs_includeUnused() async throws {
        executor.responses = [ProcessResult(stdout: "Total reclaimed space: 0B", stderr: "", exitCode: 0)]
        let result = try await service.prune(includeUnused: true)
        XCTAssertEqual(executor.calls.last?.args, ["image", "prune", "-a", "-f"])
        XCTAssertEqual(result.engine, .podman)
        XCTAssertEqual(result.reclaimedBytes, 0)
    }

    func testInvalidReference_throwsInvalidInput() async {
        do {
            _ = try service.pull(reference: "bad ref", onLine: { _ in })
            XCTFail("Expected invalidInput")
        } catch ContainerContextsError.invalidInput {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
