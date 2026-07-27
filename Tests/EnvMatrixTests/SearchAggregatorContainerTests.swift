import XCTest
@testable import EnvMatrix

private final class EmptyBrewService: HomebrewService {
    var isAvailable: Bool { false }
    var brewPath: String { "" }
    func inventory(forceRefresh: Bool) async throws -> BrewInventory { .empty }
    func run(_ operation: BrewOperation) async throws -> String { "" }
    func invalidateCache() {}
}

private final class EmptyMavenService: MavenLocalRepositoryService {
    var repositoryURL: URL { URL(fileURLWithPath: "/tmp/none") }
    var repositoryExists: Bool { false }
    func scan() throws -> [MavenArtifact] { [] }
    func totalSize() throws -> Int64 { 0 }
    func deleteArtifact(_ artifact: MavenArtifact) throws {}
    func deleteVersion(_ version: MavenArtifactVersion) throws {}
}

private final class EmptyGoService: GoLocalCacheService {
    var cacheURL: URL { URL(fileURLWithPath: "/tmp/none") }
    var cacheExists: Bool { false }
    func scan() throws -> [GoModuleArtifact] { [] }
    func totalSize() throws -> Int64 { 0 }
    func deleteModule(_ artifact: GoModuleArtifact) throws {}
    func deleteVersion(_ version: GoModuleVersion) throws {}
}

private final class EmptyNpmService: NpmService {
    func isNpmAvailable() async -> Bool { false }
    func listGlobalPackages() async throws -> [NodeGlobalPackage] { [] }
    func uninstallGlobal(_ name: String) async throws {}
    func cacheStats() async throws -> NodeCacheStats {
        NodeCacheStats(path: "/tmp/none", sizeBytes: 0)
    }
    func cacheClean() async throws {}
}

private final class EmptyPipService: PipService {
    func isPipAvailable() async -> Bool { false }
    func listUserPackages() async throws -> [PythonGlobalPackage] { [] }
    func uninstall(_ name: String) async throws {}
    func cacheStats() async throws -> PythonCacheStats {
        PythonCacheStats(path: "/tmp/none", sizeBytes: 0)
    }
    func cachePurge() async throws {}
}

private final class EmptyDockerContextService: DockerContextService {
    func isDockerAvailable() async -> Bool { false }
    func listContexts() async throws -> [DockerContext] { [] }
    func useContext(_ name: String) async throws {}
    func createContext(name: String, host: String, description: String?, tls: DockerTLSOptions?) async throws {}
    func updateContext(name: String, host: String?, description: String?, tls: DockerTLSOptions?) async throws {}
    func removeContext(_ name: String) async throws {}
    func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult {
        ContainerPingResult(engine: .docker, contextName: name, ok: false, latencyMS: 0, summary: "")
    }
}

private final class EmptyPodmanContextService: PodmanContextService {
    func isPodmanAvailable() async -> Bool { false }
    func listConnections() async throws -> [PodmanConnection] { [] }
    func setDefault(_ name: String) async throws {}
    func addConnection(name: String, uri: String, identity: String?, makeDefault: Bool) async throws {}
    func replaceConnection(oldName: String, newName: String, uri: String, identity: String?, makeDefault: Bool) async throws {}
    func removeConnection(_ name: String) async throws {}
    func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult {
        ContainerPingResult(engine: .podman, contextName: name, ok: false, latencyMS: 0, summary: "")
    }
}

private final class FakeDockerImageService: DockerImageService {
    var images: [ContainerImage] = []
    var shouldFail: Bool = false
    func list() async throws -> [ContainerImage] {
        if shouldFail { throw ContainerContextsError.cliMissing(.docker) }
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
    func inspect(id: String) async throws -> String { "" }
}

private final class FakePodmanImageService: PodmanImageService {
    var images: [ContainerImage] = []
    var shouldFail: Bool = false
    func list() async throws -> [ContainerImage] {
        if shouldFail { throw ContainerContextsError.cliMissing(.podman) }
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
    func inspect(id: String) async throws -> String { "" }
}

private final class FakeDockerContainerService: DockerContainerService {
    var instances: [ContainerInstance] = []
    var shouldFail: Bool = false
    func list(all: Bool) async throws -> [ContainerInstance] {
        if shouldFail { throw ContainerContextsError.cliMissing(.docker) }
        return instances
    }
    func start(id: String) async throws {}
    func stop(id: String) async throws {}
    func restart(id: String) async throws {}
    func remove(id: String) async throws {}
    func logs(id: String, tail: Int) async throws -> String { "" }
    func inspect(id: String) async throws -> String { "" }
}

private final class FakePodmanContainerService: PodmanContainerService {
    var instances: [ContainerInstance] = []
    var shouldFail: Bool = false
    func list(all: Bool) async throws -> [ContainerInstance] {
        if shouldFail { throw ContainerContextsError.cliMissing(.podman) }
        return instances
    }
    func start(id: String) async throws {}
    func stop(id: String) async throws {}
    func restart(id: String) async throws {}
    func remove(id: String) async throws {}
    func logs(id: String, tail: Int) async throws -> String { "" }
    func inspect(id: String) async throws -> String { "" }
}

@MainActor
final class SearchAggregatorContainerTests: XCTestCase {
    private func makeAggregator(
        dockerImages: [ContainerImage] = [],
        podmanImages: [ContainerImage] = [],
        dockerInstances: [ContainerInstance] = [],
        podmanInstances: [ContainerInstance] = [],
        dockerImageFails: Bool = false,
        podmanImageFails: Bool = false,
        dockerInstanceFails: Bool = false,
        podmanInstanceFails: Bool = false
    ) -> SearchAggregator {
        let dockerImg = FakeDockerImageService()
        dockerImg.images = dockerImages
        dockerImg.shouldFail = dockerImageFails
        let podmanImg = FakePodmanImageService()
        podmanImg.images = podmanImages
        podmanImg.shouldFail = podmanImageFails
        let dockerInst = FakeDockerContainerService()
        dockerInst.instances = dockerInstances
        dockerInst.shouldFail = dockerInstanceFails
        let podmanInst = FakePodmanContainerService()
        podmanInst.instances = podmanInstances
        podmanInst.shouldFail = podmanInstanceFails
        return SearchAggregator(
            brewService: EmptyBrewService(),
            mavenService: EmptyMavenService(),
            goService: EmptyGoService(),
            npmService: EmptyNpmService(),
            pipService: EmptyPipService(),
            dockerService: EmptyDockerContextService(),
            podmanService: EmptyPodmanContextService(),
            dockerImageService: dockerImg,
            podmanImageService: podmanImg,
            dockerContainerService: dockerInst,
            podmanContainerService: podmanInst
        )
    }

    private func sampleDockerImage(repo: String, tag: String) -> ContainerImage {
        ContainerImage(
            id: "sha256:abcd1234\(repo)",
            repository: repo,
            tag: tag,
            digest: "sha256:digest-\(repo)",
            sizeBytes: 12345,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            engine: .docker
        )
    }

    private func samplePodmanImage(repo: String, tag: String) -> ContainerImage {
        ContainerImage(
            id: "podman-id-\(repo)",
            repository: repo,
            tag: tag,
            digest: nil,
            sizeBytes: 22222,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            engine: .podman
        )
    }

    private func sampleInstance(name: String, engine: ContainerEngine, state: ContainerInstanceState) -> ContainerInstance {
        ContainerInstance(
            id: "\(engine.rawValue)-id-\(name)",
            names: [name],
            image: "nginx:latest",
            command: "nginx -g 'daemon off;'",
            state: state,
            status: state == .running ? "Up 3 hours" : "Exited (0) 5 minutes ago",
            portsSummary: "0.0.0.0:8080->80/tcp",
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            engine: engine
        )
    }

    func test_search_returnsContainerImageHits() async {
        let aggregator = makeAggregator(
            dockerImages: [sampleDockerImage(repo: "nginx", tag: "1.25")],
            podmanImages: [samplePodmanImage(repo: "nginx", tag: "latest")]
        )
        let hits = await aggregator.search("nginx")
        let imageHits = hits.filter { $0.source == .containerImage }
        XCTAssertGreaterThanOrEqual(imageHits.count, 1)
        XCTAssertTrue(imageHits.contains { $0.title == "nginx:1.25" && $0.subtitle == "docker" })
        XCTAssertTrue(imageHits.contains { $0.title == "nginx:latest" && $0.subtitle == "podman" })
    }

    func test_search_returnsContainerInstanceHits() async {
        let aggregator = makeAggregator(
            dockerInstances: [sampleInstance(name: "web", engine: .docker, state: .running)],
            podmanInstances: [sampleInstance(name: "db", engine: .podman, state: .exited)]
        )
        let hits = await aggregator.search("web")
        let instanceHits = hits.filter { $0.source == .containerInstance }
        XCTAssertGreaterThanOrEqual(instanceHits.count, 1)
        XCTAssertTrue(instanceHits.contains { $0.title == "web" })
    }

    func test_search_matchesImageKeywordsByID() async {
        let aggregator = makeAggregator(
            dockerImages: [sampleDockerImage(repo: "alpine", tag: "3.19")]
        )
        let hits = await aggregator.search("sha256:abcd1234alpine")
        XCTAssertTrue(hits.contains { $0.source == .containerImage && $0.title == "alpine:3.19" })
    }

    func test_search_matchesInstanceKeywordsByID() async {
        let aggregator = makeAggregator(
            dockerInstances: [sampleInstance(name: "api", engine: .docker, state: .running)]
        )
        let hits = await aggregator.search("docker-id-api")
        XCTAssertTrue(hits.contains { $0.source == .containerInstance && $0.title == "api" })
    }

    func test_search_toleratesFailingEngines() async {
        let aggregator = makeAggregator(
            dockerImages: [sampleDockerImage(repo: "redis", tag: "7")],
            dockerInstances: [sampleInstance(name: "cache", engine: .docker, state: .running)],
            podmanImageFails: true,
            podmanInstanceFails: true
        )
        let imageHits = await aggregator.search("redis")
        XCTAssertTrue(imageHits.contains { $0.source == .containerImage && $0.title == "redis:7" })
        let instanceHits = await aggregator.search("cache")
        XCTAssertTrue(instanceHits.contains { $0.source == .containerInstance && $0.title == "cache" })
    }

    func test_search_aggregatesBothImageAndInstanceInOneQuery() async {
        let aggregator = makeAggregator(
            dockerImages: [sampleDockerImage(repo: "nginx", tag: "1.25")],
            dockerInstances: [sampleInstance(name: "nginx-web", engine: .docker, state: .running)]
        )
        let hits = await aggregator.search("nginx")
        XCTAssertGreaterThanOrEqual(hits.filter { $0.source == .containerImage }.count, 1)
        XCTAssertGreaterThanOrEqual(hits.filter { $0.source == .containerInstance }.count, 1)
    }
}
