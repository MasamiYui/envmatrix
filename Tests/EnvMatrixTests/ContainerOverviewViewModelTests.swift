import XCTest
@testable import EnvMatrix

private final class MockDockerContextSvc: DockerContextService {
    var contexts: [DockerContext] = []
    var throwList = false
    func isDockerAvailable() async -> Bool { true }
    func listContexts() async throws -> [DockerContext] {
        if throwList { throw ContainerContextsError.cliMissing(.docker) }
        return contexts
    }
    func useContext(_ name: String) async throws {}
    func createContext(name: String, host: String, description: String?, tls: DockerTLSOptions?) async throws {}
    func updateContext(name: String, host: String?, description: String?, tls: DockerTLSOptions?) async throws {}
    func removeContext(_ name: String) async throws {}
    func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult {
        ContainerPingResult(engine: .docker, contextName: name, ok: true, latencyMS: 1, summary: "")
    }
}

private final class MockDockerImageSvc: DockerImageService {
    var images: [ContainerImage] = []
    var throwList = false
    func list() async throws -> [ContainerImage] {
        if throwList { throw ContainerContextsError.cliMissing(.docker) }
        return images
    }
    func pull(reference: String, onLine: @Sendable @escaping (String) -> Void) throws -> StreamingHandle {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        return StreamingHandle(process: p)
    }
    func tag(source: String, destination: String) async throws {}
    func remove(id: String) async throws {}
    func prune(includeUnused: Bool) async throws -> ImagePruneResult {
        ImagePruneResult(reclaimedBytes: 0, rawStdout: "", engine: .docker)
    }
    func inspect(id: String) async throws -> String { "{}" }
}

private final class MockDockerContainerSvc: DockerContainerService {
    var instances: [ContainerInstance] = []
    var throwList = false
    func list(all: Bool) async throws -> [ContainerInstance] {
        if throwList { throw ContainerContextsError.cliMissing(.docker) }
        return instances
    }
    func start(id: String) async throws {}
    func stop(id: String) async throws {}
    func restart(id: String) async throws {}
    func remove(id: String) async throws {}
    func logs(id: String, tail: Int) async throws -> String { "" }
    func inspect(id: String) async throws -> String { "{}" }
}

private final class MockPodmanContextSvc: PodmanContextService {
    var connections: [PodmanConnection] = []
    var throwList = false
    func isPodmanAvailable() async -> Bool { true }
    func listConnections() async throws -> [PodmanConnection] {
        if throwList { throw ContainerContextsError.cliMissing(.podman) }
        return connections
    }
    func setDefault(_ name: String) async throws {}
    func addConnection(name: String, uri: String, identity: String?, makeDefault: Bool) async throws {}
    func replaceConnection(oldName: String, newName: String, uri: String, identity: String?, makeDefault: Bool) async throws {}
    func removeConnection(_ name: String) async throws {}
    func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult {
        ContainerPingResult(engine: .podman, contextName: name, ok: true, latencyMS: 1, summary: "")
    }
}

private final class MockPodmanImageSvc: PodmanImageService {
    var images: [ContainerImage] = []
    var throwList = false
    func list() async throws -> [ContainerImage] {
        if throwList { throw ContainerContextsError.cliMissing(.podman) }
        return images
    }
    func pull(reference: String, onLine: @Sendable @escaping (String) -> Void) throws -> StreamingHandle {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        return StreamingHandle(process: p)
    }
    func tag(source: String, destination: String) async throws {}
    func remove(id: String) async throws {}
    func prune(includeUnused: Bool) async throws -> ImagePruneResult {
        ImagePruneResult(reclaimedBytes: 0, rawStdout: "", engine: .podman)
    }
    func inspect(id: String) async throws -> String { "{}" }
}

private final class MockPodmanContainerSvc: PodmanContainerService {
    var instances: [ContainerInstance] = []
    var throwList = false
    func list(all: Bool) async throws -> [ContainerInstance] {
        if throwList { throw ContainerContextsError.cliMissing(.podman) }
        return instances
    }
    func start(id: String) async throws {}
    func stop(id: String) async throws {}
    func restart(id: String) async throws {}
    func remove(id: String) async throws {}
    func logs(id: String, tail: Int) async throws -> String { "" }
    func inspect(id: String) async throws -> String { "{}" }
}

@MainActor
final class ContainerOverviewViewModelTests: XCTestCase {
    private func makeImage(_ repo: String, engine: ContainerEngine = .docker) -> ContainerImage {
        ContainerImage(
            id: "sha256:\(repo)",
            repository: repo,
            tag: "latest",
            digest: nil,
            sizeBytes: 1_000,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            engine: engine
        )
    }

    private func makeInstance(_ name: String, state: ContainerInstanceState, engine: ContainerEngine = .docker) -> ContainerInstance {
        ContainerInstance(
            id: name,
            names: [name],
            image: "nginx",
            command: "sh",
            state: state,
            status: state.rawValue,
            portsSummary: "",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            engine: engine
        )
    }

    func test_refresh_dockerCounts() async {
        let ctxSvc = MockDockerContextSvc()
        ctxSvc.contexts = [
            DockerContext(name: "x", description: "", endpoint: "unix:///var/run/docker.sock", contextType: "moby", isCurrent: true)
        ]
        let imgSvc = MockDockerImageSvc()
        imgSvc.images = [makeImage("a"), makeImage("b"), makeImage("c")]
        let cntSvc = MockDockerContainerSvc()
        cntSvc.instances = [
            makeInstance("c1", state: .running),
            makeInstance("c2", state: .running),
            makeInstance("c3", state: .exited)
        ]
        let podmanCtxSvc = MockPodmanContextSvc()
        let podmanImgSvc = MockPodmanImageSvc()
        let podmanCntSvc = MockPodmanContainerSvc()

        let vm = ContainerOverviewViewModel(
            dockerImage: imgSvc,
            dockerContainer: cntSvc,
            dockerContext: ctxSvc,
            podmanImage: podmanImgSvc,
            podmanContainer: podmanCntSvc,
            podmanContext: podmanCtxSvc
        )
        await vm.refresh()

        XCTAssertEqual(vm.dockerContextName, "x")
        XCTAssertEqual(vm.dockerImages, 3)
        XCTAssertEqual(vm.dockerRunning, 2)
        XCTAssertEqual(vm.dockerStopped, 1)
        XCTAssertFalse(vm.isLoading)
    }

    func test_refresh_podmanCounts() async {
        let dockerCtxSvc = MockDockerContextSvc()
        let dockerImgSvc = MockDockerImageSvc()
        let dockerCntSvc = MockDockerContainerSvc()
        let podmanCtxSvc = MockPodmanContextSvc()
        podmanCtxSvc.connections = [
            PodmanConnection(name: "podman-default", uri: "unix:///tmp/podman.sock", identity: "", isDefault: true)
        ]
        let podmanImgSvc = MockPodmanImageSvc()
        podmanImgSvc.images = [
            makeImage("a", engine: .podman),
            makeImage("b", engine: .podman),
            makeImage("c", engine: .podman)
        ]
        let podmanCntSvc = MockPodmanContainerSvc()
        podmanCntSvc.instances = [
            makeInstance("p1", state: .running, engine: .podman),
            makeInstance("p2", state: .running, engine: .podman),
            makeInstance("p3", state: .exited, engine: .podman)
        ]

        let vm = ContainerOverviewViewModel(
            dockerImage: dockerImgSvc,
            dockerContainer: dockerCntSvc,
            dockerContext: dockerCtxSvc,
            podmanImage: podmanImgSvc,
            podmanContainer: podmanCntSvc,
            podmanContext: podmanCtxSvc
        )
        await vm.refresh()

        XCTAssertEqual(vm.podmanConnectionName, "podman-default")
        XCTAssertEqual(vm.podmanImages, 3)
        XCTAssertEqual(vm.podmanRunning, 2)
        XCTAssertEqual(vm.podmanStopped, 1)
        XCTAssertFalse(vm.isLoading)
    }

    func test_refresh_failuresAreIsolated() async {
        let ctxSvc = MockDockerContextSvc()
        ctxSvc.throwList = true
        let imgSvc = MockDockerImageSvc()
        imgSvc.images = [makeImage("a")]
        let cntSvc = MockDockerContainerSvc()
        cntSvc.throwList = true
        let podmanCtxSvc = MockPodmanContextSvc()
        let podmanImgSvc = MockPodmanImageSvc()
        let podmanCntSvc = MockPodmanContainerSvc()

        let vm = ContainerOverviewViewModel(
            dockerImage: imgSvc,
            dockerContainer: cntSvc,
            dockerContext: ctxSvc,
            podmanImage: podmanImgSvc,
            podmanContainer: podmanCntSvc,
            podmanContext: podmanCtxSvc
        )
        await vm.refresh()

        XCTAssertNil(vm.dockerContextName)
        XCTAssertEqual(vm.dockerImages, 1)
        XCTAssertEqual(vm.dockerRunning, 0)
        XCTAssertEqual(vm.dockerStopped, 0)
    }
}
