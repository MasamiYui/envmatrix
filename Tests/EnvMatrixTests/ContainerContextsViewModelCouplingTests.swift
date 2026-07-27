import XCTest
@testable import EnvMatrix

private final class MockDockerContextService: DockerContextService {
    func isDockerAvailable() async -> Bool { true }
    func listContexts() async throws -> [DockerContext] { [] }
    func useContext(_ name: String) async throws {}
    func createContext(name: String, host: String, description: String?, tls: DockerTLSOptions?) async throws {
        fatalError("not used")
    }
    func updateContext(name: String, host: String?, description: String?, tls: DockerTLSOptions?) async throws {
        fatalError("not used")
    }
    func removeContext(_ name: String) async throws { fatalError("not used") }
    func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult {
        ContainerPingResult(engine: .docker, contextName: name, ok: true, latencyMS: 0, summary: "")
    }
}

private final class MockPodmanContextService: PodmanContextService {
    func isPodmanAvailable() async -> Bool { true }
    func listConnections() async throws -> [PodmanConnection] { [] }
    func setDefault(_ name: String) async throws {}
    func addConnection(name: String, uri: String, identity: String?, makeDefault: Bool) async throws {
        fatalError("not used")
    }
    func replaceConnection(oldName: String, newName: String, uri: String, identity: String?, makeDefault: Bool) async throws {
        fatalError("not used")
    }
    func removeConnection(_ name: String) async throws { fatalError("not used") }
    func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult {
        ContainerPingResult(engine: .podman, contextName: name, ok: true, latencyMS: 0, summary: "")
    }
}

private final class NoopDockerImageService: DockerImageService, @unchecked Sendable {
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

private final class NoopPodmanImageService: PodmanImageService, @unchecked Sendable {
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

private final class NoopDockerContainerService: DockerContainerService, @unchecked Sendable {
    func list(all: Bool) async throws -> [ContainerInstance] { [] }
    func start(id: String) async throws {}
    func stop(id: String) async throws {}
    func restart(id: String) async throws {}
    func remove(id: String) async throws {}
    func logs(id: String, tail: Int) async throws -> String { "" }
    func inspect(id: String) async throws -> String { "" }
}

private final class NoopPodmanContainerService: PodmanContainerService, @unchecked Sendable {
    func list(all: Bool) async throws -> [ContainerInstance] { [] }
    func start(id: String) async throws {}
    func stop(id: String) async throws {}
    func restart(id: String) async throws {}
    func remove(id: String) async throws {}
    func logs(id: String, tail: Int) async throws -> String { "" }
    func inspect(id: String) async throws -> String { "" }
}

@MainActor
final class ContainerContextsViewModelCouplingTests: XCTestCase {
    private func makeViewModel() -> ContainerContextsViewModel {
        ContainerContextsViewModel(
            dockerService: MockDockerContextService(),
            podmanService: MockPodmanContextService(),
            dockerImageService: NoopDockerImageService(),
            podmanImageService: NoopPodmanImageService(),
            dockerContainerService: NoopDockerContainerService(),
            podmanContainerService: NoopPodmanContainerService()
        )
    }

    func test_useDocker_marksSubVMStale() async {
        let vm = makeViewModel()
        XCTAssertFalse(vm.imagesVMDocker.isStale)
        XCTAssertFalse(vm.instancesVMDocker.isStale)

        await vm.useDocker("ctx1")

        XCTAssertTrue(vm.imagesVMDocker.isStale)
        XCTAssertTrue(vm.instancesVMDocker.isStale)
        XCTAssertFalse(vm.imagesVMPodman.isStale)
        XCTAssertFalse(vm.instancesVMPodman.isStale)
    }

    func test_setPodmanDefault_marksSubVMStale() async {
        let vm = makeViewModel()
        XCTAssertFalse(vm.imagesVMPodman.isStale)
        XCTAssertFalse(vm.instancesVMPodman.isStale)

        await vm.setPodmanDefault("machine")

        XCTAssertTrue(vm.imagesVMPodman.isStale)
        XCTAssertTrue(vm.instancesVMPodman.isStale)
        XCTAssertFalse(vm.imagesVMDocker.isStale)
        XCTAssertFalse(vm.instancesVMDocker.isStale)
    }

    func test_defaultSelectedTab_isContexts() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.selectedTab, .contexts)
    }
}
