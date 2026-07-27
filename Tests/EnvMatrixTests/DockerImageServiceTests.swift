import XCTest
@testable import EnvMatrix

private final class MockStreamingProcessExecutor: StreamingProcessExecutor {
    struct Call {
        let executable: URL
        let args: [String]
    }

    var runCalls: [Call] = []
    var streamCalls: [Call] = []
    var spawnCalls: [Call] = []
    var responses: [[String]: ProcessResult] = [:]
    var defaultResponse: ProcessResult = ProcessResult(stdout: "", stderr: "", exitCode: 0)
    var spawnLines: [String] = []

    func run(executable: URL, args: [String], timeout: TimeInterval?) async throws -> ProcessResult {
        runCalls.append(Call(executable: executable, args: args))
        if let r = responses[args] { return r }
        return defaultResponse
    }

    func stream(executable: URL, args: [String], onLine: @Sendable @escaping (String) -> Void) async throws -> ProcessResult {
        streamCalls.append(Call(executable: executable, args: args))
        for line in spawnLines { onLine(line) }
        if let r = responses[args] { return r }
        return defaultResponse
    }

    func spawn(executable: URL, args: [String], onLine: @Sendable @escaping (String) -> Void) -> StreamingHandle {
        spawnCalls.append(Call(executable: executable, args: args))
        for line in spawnLines { onLine(line) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        return StreamingHandle(process: process)
    }
}

private final class StubShellPathResolverForImages: ShellPathResolver {
    let dirs: [URL]
    init(dirs: [URL]) { self.dirs = dirs }
    func resolvePathDirs() -> [URL] { dirs }
}

final class DockerImageServiceTests: XCTestCase {
    private var tempBinDir: URL!
    private var executor: MockStreamingProcessExecutor!
    private var service: DefaultDockerImageService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempBinDir = try DockerTestFixtures.makeTempBinDir(binaryName: "docker")
        executor = MockStreamingProcessExecutor()
        service = DefaultDockerImageService(
            executor: executor,
            shellPathResolver: StubShellPathResolverForImages(dirs: [tempBinDir]),
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

    func testList_parsesJSONLines() async throws {
        let stdout = """
{"Repository":"nginx","Tag":"latest","ID":"sha256:aaa","Digest":"<none>","Size":"12.3MB","CreatedAt":"2024-01-15 09:23:11 +0800 CST","CreatedSince":"3 months ago"}
{"Repository":"redis","Tag":"7","ID":"sha256:bbb","Digest":"sha256:deadbeef","Size":"100MB","CreatedAt":"2024-02-20 10:00:00 +0800 CST","CreatedSince":"2 months ago"}
"""
        executor.responses[["images", "--format", "{{json .}}"]] =
            ProcessResult(stdout: stdout, stderr: "", exitCode: 0)

        let images = try await service.list()

        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(images[0].repository, "nginx")
        XCTAssertEqual(images[0].tag, "latest")
        XCTAssertEqual(images[0].sizeBytes, 12_300_000)
        XCTAssertNil(images[0].digest)
        XCTAssertEqual(images[1].repository, "redis")
        XCTAssertEqual(images[1].tag, "7")
        XCTAssertEqual(images[1].sizeBytes, 100_000_000)
        XCTAssertEqual(images[1].digest, "sha256:deadbeef")
    }

    func testPrune_parsesReclaimedBytes() async throws {
        executor.responses[["image", "prune", "-f"]] = ProcessResult(
            stdout: "Deleted Images:\nuntagged: foo\n\nTotal reclaimed space: 1.5MB\n",
            stderr: "",
            exitCode: 0
        )

        let result = try await service.prune(includeUnused: false)

        XCTAssertEqual(result.reclaimedBytes, 1_500_000)
        XCTAssertEqual(result.engine, .docker)
    }

    func testInvalidReference_throwsInvalidInput() {
        do {
            _ = try service.pull(reference: "weird ref") { _ in }
            XCTFail("Expected invalidInput to be thrown")
        } catch let ContainerContextsError.invalidInput(reason) {
            XCTAssertFalse(reason.isEmpty)
        } catch {
            XCTFail("Expected ContainerContextsError.invalidInput, got \(error)")
        }
    }
}
