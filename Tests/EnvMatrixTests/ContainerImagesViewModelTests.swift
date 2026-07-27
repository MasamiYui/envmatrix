import XCTest
@testable import EnvMatrix

private final class MockDockerImageService: DockerImageService {
    var listResult: [ContainerImage] = []
    var listError: Error?
    var pullError: Error?
    var pullHandle: StreamingHandle?
    var pullLines: [String] = []
    var removeError: Error?
    var tagError: Error?
    var pruneResult: ImagePruneResult = ImagePruneResult(reclaimedBytes: 0, rawStdout: "", engine: .docker)
    var pruneError: Error?
    var inspectResult: String = "{}"
    var inspectError: Error?

    func list() async throws -> [ContainerImage] {
        if let err = listError { throw err }
        return listResult
    }

    func pull(reference: String, onLine: @Sendable @escaping (String) -> Void) throws -> StreamingHandle {
        if let err = pullError { throw err }
        for line in pullLines { onLine(line) }
        if let handle = pullHandle { return handle }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        return StreamingHandle(process: process)
    }

    func tag(source: String, destination: String) async throws {
        if let err = tagError { throw err }
    }

    func remove(id: String) async throws {
        if let err = removeError { throw err }
    }

    func prune(includeUnused: Bool) async throws -> ImagePruneResult {
        if let err = pruneError { throw err }
        return pruneResult
    }

    func inspect(id: String) async throws -> String {
        if let err = inspectError { throw err }
        return inspectResult
    }
}

@MainActor
final class ContainerImagesViewModelTests: XCTestCase {
    private func sampleImages() -> [ContainerImage] {
        [
            ContainerImage(
                id: "sha256:aaa",
                repository: "nginx",
                tag: "latest",
                digest: nil,
                sizeBytes: 12_300_000,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                engine: .docker
            ),
            ContainerImage(
                id: "sha256:bbb",
                repository: "redis",
                tag: "7",
                digest: nil,
                sizeBytes: 100_000_000,
                createdAt: Date(timeIntervalSince1970: 1_700_100_000),
                engine: .docker
            )
        ]
    }

    func test_refresh_writesImages() async {
        let mock = MockDockerImageService()
        mock.listResult = sampleImages()
        let vm = ContainerImagesViewModel(engine: .docker, dockerService: mock)

        await vm.refresh()

        XCTAssertEqual(vm.images.count, 2)
        XCTAssertEqual(vm.images.first?.repository, "nginx")
        XCTAssertFalse(vm.isBusy)
        XCTAssertFalse(vm.isStale)
        XCTAssertNil(vm.errorMessage)
    }

    func test_pull_invalid_appendsErrorLine() async {
        let mock = MockDockerImageService()
        mock.pullError = ContainerContextsError.invalidInput("reference contains forbidden characters")
        let vm = ContainerImagesViewModel(engine: .docker, dockerService: mock)

        await vm.pull(reference: "bad ref")

        XCTAssertFalse(vm.pullLog.isEmpty)
        XCTAssertTrue(vm.pullLog.contains(where: { $0.lowercased().contains("error") }))
        XCTAssertFalse(vm.isBusy)
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_cancelPull_setsIsBusyFalse() async {
        let mock = MockDockerImageService()
        mock.listResult = []
        let vm = ContainerImagesViewModel(engine: .docker, dockerService: mock)

        await vm.pull(reference: "nginx:latest")
        vm.cancelPull()

        XCTAssertFalse(vm.isBusy)
        XCTAssertNil(vm.pullHandle)
        XCTAssertTrue(vm.pullLog.contains(where: { $0.contains("Cancelled") }))
    }

    func test_filteredSortedImages_keywordAndSort() async {
        let mock = MockDockerImageService()
        mock.listResult = sampleImages()
        let vm = ContainerImagesViewModel(engine: .docker, dockerService: mock)
        await vm.refresh()

        vm.keyword = "red"
        XCTAssertEqual(vm.filteredSortedImages.count, 1)
        XCTAssertEqual(vm.filteredSortedImages.first?.repository, "redis")

        vm.keyword = ""
        vm.sort = .size
        XCTAssertEqual(vm.filteredSortedImages.first?.repository, "redis")
    }

    func test_markStale_setsFlag() {
        let vm = ContainerImagesViewModel(engine: .docker, dockerService: MockDockerImageService())
        XCTAssertFalse(vm.isStale)
        vm.markStale()
        XCTAssertTrue(vm.isStale)
    }
}
