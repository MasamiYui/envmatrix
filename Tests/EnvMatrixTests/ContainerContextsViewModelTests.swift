import XCTest
@testable import EnvMatrix

final class FakeDockerService: DockerContextService {
    var available: Bool = true
    var contexts: [DockerContext] = []
    var listError: Error?
    var pingResult: ContainerPingResult?
    var pingError: Error?

    func isDockerAvailable() async -> Bool { available }

    func listContexts() async throws -> [DockerContext] {
        if let err = listError { throw err }
        return contexts
    }

    func useContext(_ name: String) async throws {
        contexts = contexts.map {
            DockerContext(
                name: $0.name,
                description: $0.description,
                endpoint: $0.endpoint,
                contextType: $0.contextType,
                isCurrent: $0.name == name,
                tlsEnabled: $0.tlsEnabled,
                skipTLSVerify: $0.skipTLSVerify
            )
        }
    }

    func createContext(name: String, host: String, description: String?, tls: DockerTLSOptions?) async throws {}
    func updateContext(name: String, host: String?, description: String?, tls: DockerTLSOptions?) async throws {}
    func removeContext(_ name: String) async throws {}

    func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult {
        if let err = pingError { throw err }
        if let result = pingResult { return result }
        return ContainerPingResult(engine: .docker, contextName: name, ok: true, latencyMS: 0, summary: "")
    }
}

final class FakePodmanService: PodmanContextService {
    var available: Bool = true
    var connections: [PodmanConnection] = []
    var listError: Error?
    var pingResult: ContainerPingResult?

    func isPodmanAvailable() async -> Bool { available }

    func listConnections() async throws -> [PodmanConnection] {
        if let err = listError { throw err }
        return connections
    }

    func setDefault(_ name: String) async throws {}
    func addConnection(name: String, uri: String, identity: String?, makeDefault: Bool) async throws {}
    func replaceConnection(oldName: String, newName: String, uri: String, identity: String?, makeDefault: Bool) async throws {}
    func removeConnection(_ name: String) async throws {}

    func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult {
        if let result = pingResult { return result }
        return ContainerPingResult(engine: .podman, contextName: name, ok: true, latencyMS: 0, summary: "")
    }
}

// Tests for ContainerContextsViewModel state changes with fake services.
@MainActor
final class ContainerContextsViewModelTests: XCTestCase {
    private func sampleDockerContexts() -> [DockerContext] {
        [
            DockerContext(name: "default", description: "", endpoint: "unix:///var/run/docker.sock", contextType: "moby", isCurrent: true),
            DockerContext(name: "colima", description: "", endpoint: "unix:///Users/me/.colima/default/docker.sock", contextType: "moby", isCurrent: false),
            DockerContext(name: "remote", description: "", endpoint: "tcp://1.2.3.4:2376", contextType: "moby", isCurrent: false)
        ]
    }

    private func samplePodmanConnections() -> [PodmanConnection] {
        [
            PodmanConnection(name: "machine", uri: "unix:///run/user/501/podman/podman.sock", identity: "", isDefault: true),
            PodmanConnection(name: "remote", uri: "ssh://user@host/run/podman/podman.sock", identity: "/tmp/id", isDefault: false)
        ]
    }

    func test_refresh_populatesBothLists_whenAvailable() async {
        let docker = FakeDockerService()
        docker.available = true
        docker.contexts = sampleDockerContexts()
        let podman = FakePodmanService()
        podman.available = true
        podman.connections = samplePodmanConnections()

        let vm = ContainerContextsViewModel(dockerService: docker, podmanService: podman)
        await vm.refresh()

        XCTAssertTrue(vm.dockerAvailable)
        XCTAssertTrue(vm.podmanAvailable)
        XCTAssertEqual(vm.dockerContexts.count, 3)
        XCTAssertEqual(vm.podmanConnections.count, 2)
        XCTAssertNil(vm.dockerError)
        XCTAssertNil(vm.podmanError)
    }

    func test_useDocker_updatesCurrent() async {
        let docker = FakeDockerService()
        docker.contexts = sampleDockerContexts()
        let podman = FakePodmanService()
        podman.connections = samplePodmanConnections()

        let vm = ContainerContextsViewModel(dockerService: docker, podmanService: podman)
        await vm.refresh()

        await vm.useDocker("colima")

        XCTAssertEqual(vm.dockerContexts.first(where: { $0.isCurrent })?.name, "colima")
        XCTAssertNil(vm.dockerError)
    }

    func test_partialAvailability_dockerMissing_doesNotAffectPodman() async {
        let docker = FakeDockerService()
        docker.available = false
        let podman = FakePodmanService()
        podman.available = true
        podman.connections = samplePodmanConnections()

        let vm = ContainerContextsViewModel(dockerService: docker, podmanService: podman)
        await vm.refresh()

        XCTAssertFalse(vm.dockerAvailable)
        XCTAssertTrue(vm.dockerContexts.isEmpty)
        XCTAssertTrue(vm.podmanAvailable)
        XCTAssertGreaterThan(vm.podmanConnections.count, 0)
        XCTAssertNil(vm.podmanError)
    }

    func test_ping_writesResultKeyed() async {
        let docker = FakeDockerService()
        docker.contexts = sampleDockerContexts()
        docker.pingResult = ContainerPingResult(
            engine: .docker,
            contextName: "colima",
            ok: true,
            latencyMS: 12,
            summary: "Client: 24 Server: 24"
        )
        let podman = FakePodmanService()

        let vm = ContainerContextsViewModel(dockerService: docker, podmanService: podman)
        await vm.ping(engine: .docker, name: "colima")

        XCTAssertEqual(vm.pingResults["docker/colima"]?.ok, true)
        XCTAssertEqual(vm.pingResults["docker/colima"]?.latencyMS, 12)
    }
}
