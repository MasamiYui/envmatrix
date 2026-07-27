import XCTest
@testable import EnvMatrix

private final class StaleDockerContextService: DockerContextService {
    func isDockerAvailable() async -> Bool { true }
    func listContexts() async throws -> [DockerContext] { [] }
    func useContext(_ name: String) async throws {}
    func createContext(name: String, host: String, description: String?, tls: DockerTLSOptions?) async throws {}
    func updateContext(name: String, host: String?, description: String?, tls: DockerTLSOptions?) async throws {}
    func removeContext(_ name: String) async throws {}
    func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult {
        ContainerPingResult(engine: .docker, contextName: name, ok: true, latencyMS: 0, summary: "")
    }
}

private final class StalePodmanContextService: PodmanContextService {
    func isPodmanAvailable() async -> Bool { true }
    func listConnections() async throws -> [PodmanConnection] { [] }
    func setDefault(_ name: String) async throws {}
    func addConnection(name: String, uri: String, identity: String?, makeDefault: Bool) async throws {}
    func replaceConnection(oldName: String, newName: String, uri: String, identity: String?, makeDefault: Bool) async throws {}
    func removeConnection(_ name: String) async throws {}
    func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult {
        ContainerPingResult(engine: .podman, contextName: name, ok: true, latencyMS: 0, summary: "")
    }
}

private final class StubDockerImageService: DockerImageService, @unchecked Sendable {
    func list() async throws -> [ContainerImage] { [] }
    func pull(reference: String, onLine: @Sendable @escaping (String) -> Void) throws -> StreamingHandle {
        throw ContainerContextsError.invalidInput("not used")
    }
    func tag(source: String, destination: String) async throws {}
    func remove(id: String) async throws {}
    func prune(includeUnused: Bool) async throws -> ImagePruneResult {
        ImagePruneResult(reclaimedBytes: 0, rawStdout: "", engine: .docker)
    }
    func inspect(id: String) async throws -> String { "" }
}

private final class StubPodmanImageService: PodmanImageService, @unchecked Sendable {
    func list() async throws -> [ContainerImage] { [] }
    func pull(reference: String, onLine: @Sendable @escaping (String) -> Void) throws -> StreamingHandle {
        throw ContainerContextsError.invalidInput("not used")
    }
    func tag(source: String, destination: String) async throws {}
    func remove(id: String) async throws {}
    func prune(includeUnused: Bool) async throws -> ImagePruneResult {
        ImagePruneResult(reclaimedBytes: 0, rawStdout: "", engine: .podman)
    }
    func inspect(id: String) async throws -> String { "" }
}

private final class StubDockerContainerService: DockerContainerService, @unchecked Sendable {
    func list(all: Bool) async throws -> [ContainerInstance] { [] }
    func start(id: String) async throws {}
    func stop(id: String) async throws {}
    func restart(id: String) async throws {}
    func remove(id: String) async throws {}
    func logs(id: String, tail: Int) async throws -> String { "" }
    func inspect(id: String) async throws -> String { "" }
}

private final class StubPodmanContainerService: PodmanContainerService, @unchecked Sendable {
    func list(all: Bool) async throws -> [ContainerInstance] { [] }
    func start(id: String) async throws {}
    func stop(id: String) async throws {}
    func restart(id: String) async throws {}
    func remove(id: String) async throws {}
    func logs(id: String, tail: Int) async throws -> String { "" }
    func inspect(id: String) async throws -> String { "" }
}

@MainActor
final class ContainerContextsViewModelStaleTests: XCTestCase {
    private func makeViewModel() -> ContainerContextsViewModel {
        ContainerContextsViewModel(
            dockerService: StaleDockerContextService(),
            podmanService: StalePodmanContextService(),
            dockerImageService: StubDockerImageService(),
            podmanImageService: StubPodmanImageService(),
            dockerContainerService: StubDockerContainerService(),
            podmanContainerService: StubPodmanContainerService()
        )
    }

    func test_defaultSelectedTab_isContexts() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.selectedTab, .contexts)
    }

    func test_subViewModels_startFresh() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.imagesVMDocker.isStale)
        XCTAssertFalse(vm.imagesVMPodman.isStale)
        XCTAssertFalse(vm.instancesVMDocker.isStale)
        XCTAssertFalse(vm.instancesVMPodman.isStale)
    }

    func test_useDocker_marksDockerSubViewModelsStale() async {
        let vm = makeViewModel()
        await vm.useDocker("colima")

        XCTAssertTrue(vm.imagesVMDocker.isStale)
        XCTAssertTrue(vm.instancesVMDocker.isStale)
        XCTAssertFalse(vm.imagesVMPodman.isStale)
        XCTAssertFalse(vm.instancesVMPodman.isStale)
        XCTAssertNil(vm.dockerError)
    }

    func test_setPodmanDefault_marksPodmanSubViewModelsStale() async {
        let vm = makeViewModel()
        await vm.setPodmanDefault("machine")

        XCTAssertTrue(vm.imagesVMPodman.isStale)
        XCTAssertTrue(vm.instancesVMPodman.isStale)
        XCTAssertFalse(vm.imagesVMDocker.isStale)
        XCTAssertFalse(vm.instancesVMDocker.isStale)
        XCTAssertNil(vm.podmanError)
    }
}
