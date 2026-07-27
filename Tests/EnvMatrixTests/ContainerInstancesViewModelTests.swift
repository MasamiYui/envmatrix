import XCTest
@testable import EnvMatrix

private final class MockDockerContainerService: DockerContainerService {
    var listResult: [ContainerInstance] = []
    var listError: Error?
    var startError: Error?
    var stopError: Error?
    var restartError: Error?
    var removeError: Error?
    var logsResult: String = ""
    var logsError: Error?
    var inspectResult: String = "{}"
    var inspectError: Error?
    var startCalls: [String] = []
    var stopCalls: [String] = []
    var logsCalls: [(String, Int)] = []

    func list(all: Bool) async throws -> [ContainerInstance] {
        if let err = listError { throw err }
        return listResult
    }

    func start(id: String) async throws {
        startCalls.append(id)
        if let err = startError { throw err }
    }

    func stop(id: String) async throws {
        stopCalls.append(id)
        if let err = stopError { throw err }
    }

    func restart(id: String) async throws {
        if let err = restartError { throw err }
    }

    func remove(id: String) async throws {
        if let err = removeError { throw err }
    }

    func logs(id: String, tail: Int) async throws -> String {
        logsCalls.append((id, tail))
        if let err = logsError { throw err }
        return logsResult
    }

    func inspect(id: String) async throws -> String {
        if let err = inspectError { throw err }
        return inspectResult
    }
}

@MainActor
final class ContainerInstancesViewModelTests: XCTestCase {
    private func sampleInstances() -> [ContainerInstance] {
        [
            ContainerInstance(
                id: "id-1",
                names: ["nginx-1"],
                image: "nginx:latest",
                command: "nginx -g daemon off;",
                state: .running,
                status: "Up 5 minutes",
                portsSummary: "0.0.0.0:80->80/tcp",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                engine: .docker
            ),
            ContainerInstance(
                id: "id-2",
                names: ["redis-1"],
                image: "redis:7",
                command: "redis-server",
                state: .exited,
                status: "Exited (0) 1 hour ago",
                portsSummary: "",
                createdAt: Date(timeIntervalSince1970: 1_700_100_000),
                engine: .docker
            ),
            ContainerInstance(
                id: "id-3",
                names: ["paused-1"],
                image: "busybox",
                command: "sleep 100",
                state: .paused,
                status: "Paused",
                portsSummary: "",
                createdAt: Date(timeIntervalSince1970: 1_700_200_000),
                engine: .docker
            )
        ]
    }

    func test_refresh_writesInstances() async {
        let mock = MockDockerContainerService()
        mock.listResult = sampleInstances()
        let vm = ContainerInstancesViewModel(engine: .docker, dockerService: mock)

        await vm.refresh()

        XCTAssertEqual(vm.instances.count, 3)
        XCTAssertFalse(vm.isBusy)
        XCTAssertFalse(vm.isStale)
        XCTAssertNil(vm.errorMessage)
    }

    func test_viewLogs_setsLogsSheet() async {
        let mock = MockDockerContainerService()
        mock.logsResult = "line1\nline2\n"
        let vm = ContainerInstancesViewModel(engine: .docker, dockerService: mock)

        await vm.viewLogs(id: "id-1", tail: 100)

        XCTAssertNotNil(vm.logsSheet)
        XCTAssertEqual(vm.logsSheet?.instanceID, "id-1")
        XCTAssertEqual(vm.logsSheet?.content, "line1\nline2\n")
        XCTAssertEqual(mock.logsCalls.first?.0, "id-1")
        XCTAssertEqual(mock.logsCalls.first?.1, 100)
    }

    func test_filter_running_onlyRunning() async {
        let mock = MockDockerContainerService()
        mock.listResult = sampleInstances()
        let vm = ContainerInstancesViewModel(engine: .docker, dockerService: mock)
        await vm.refresh()

        vm.filter = .running
        let filtered = vm.filteredInstances

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.state, .running)
        XCTAssertEqual(filtered.first?.image, "nginx:latest")
    }

    func test_filter_exited_onlyExited() async {
        let mock = MockDockerContainerService()
        mock.listResult = sampleInstances()
        let vm = ContainerInstancesViewModel(engine: .docker, dockerService: mock)
        await vm.refresh()

        vm.filter = .exited
        let filtered = vm.filteredInstances

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.state, .exited)
    }

    func test_keyword_filtersByNameOrImage() async {
        let mock = MockDockerContainerService()
        mock.listResult = sampleInstances()
        let vm = ContainerInstancesViewModel(engine: .docker, dockerService: mock)
        await vm.refresh()

        vm.keyword = "redis"
        XCTAssertEqual(vm.filteredInstances.count, 1)
        XCTAssertEqual(vm.filteredInstances.first?.id, "id-2")
    }

    func test_markStale_setsFlag() {
        let vm = ContainerInstancesViewModel(engine: .docker, dockerService: MockDockerContainerService())
        XCTAssertFalse(vm.isStale)
        vm.markStale()
        XCTAssertTrue(vm.isStale)
    }
}
