import XCTest
@testable import EnvMatrix

private final class MockDockerImageServiceForDiag: DockerImageService {
    var images: [ContainerImage] = []
    var shouldThrow = false
    func list() async throws -> [ContainerImage] {
        if shouldThrow { throw ContainerContextsError.commandFailed(.docker, "boom") }
        return images
    }
    func pull(reference: String, onLine: @Sendable @escaping (String) -> Void) throws -> StreamingHandle {
        throw ContainerContextsError.cliMissing(.docker)
    }
    func tag(source: String, destination: String) async throws {}
    func remove(id: String) async throws {}
    func prune(includeUnused: Bool) async throws -> ImagePruneResult {
        ImagePruneResult(reclaimedBytes: 0, rawStdout: "", engine: .docker)
    }
    func inspect(id: String) async throws -> String { "" }
}

private final class MockDockerContainerServiceForDiag: DockerContainerService {
    var instances: [ContainerInstance] = []
    var shouldThrow = false
    func list(all: Bool) async throws -> [ContainerInstance] {
        if shouldThrow { throw ContainerContextsError.commandFailed(.docker, "boom") }
        return instances
    }
    func start(id: String) async throws {}
    func stop(id: String) async throws {}
    func restart(id: String) async throws {}
    func remove(id: String) async throws {}
    func logs(id: String, tail: Int) async throws -> String { "" }
    func inspect(id: String) async throws -> String { "" }
}

private final class MockPodmanImageServiceForDiag: PodmanImageService {
    var images: [ContainerImage] = []
    var shouldThrow = false
    func list() async throws -> [ContainerImage] {
        if shouldThrow { throw ContainerContextsError.commandFailed(.podman, "boom") }
        return images
    }
    func pull(reference: String, onLine: @Sendable @escaping (String) -> Void) throws -> StreamingHandle {
        throw ContainerContextsError.cliMissing(.podman)
    }
    func tag(source: String, destination: String) async throws {}
    func remove(id: String) async throws {}
    func prune(includeUnused: Bool) async throws -> ImagePruneResult {
        ImagePruneResult(reclaimedBytes: 0, rawStdout: "", engine: .podman)
    }
    func inspect(id: String) async throws -> String { "" }
}

private final class MockPodmanContainerServiceForDiag: PodmanContainerService {
    var instances: [ContainerInstance] = []
    var shouldThrow = false
    func list(all: Bool) async throws -> [ContainerInstance] {
        if shouldThrow { throw ContainerContextsError.commandFailed(.podman, "boom") }
        return instances
    }
    func start(id: String) async throws {}
    func stop(id: String) async throws {}
    func restart(id: String) async throws {}
    func remove(id: String) async throws {}
    func logs(id: String, tail: Int) async throws -> String { "" }
    func inspect(id: String) async throws -> String { "" }
}

private final class StubDockerContextServiceForDiag: DockerContextService {
    var available = true
    var contexts: [DockerContext] = []
    func isDockerAvailable() async -> Bool { available }
    func listContexts() async throws -> [DockerContext] { contexts }
    func useContext(_ name: String) async throws {}
    func createContext(name: String, host: String, description: String?, tls: DockerTLSOptions?) async throws {}
    func updateContext(name: String, host: String?, description: String?, tls: DockerTLSOptions?) async throws {}
    func removeContext(_ name: String) async throws {}
    func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult {
        ContainerPingResult(engine: .docker, contextName: name, ok: true, latencyMS: 0, summary: "")
    }
}

private final class StubPodmanContextServiceForDiag: PodmanContextService {
    var available = true
    var connections: [PodmanConnection] = []
    func isPodmanAvailable() async -> Bool { available }
    func listConnections() async throws -> [PodmanConnection] { connections }
    func setDefault(_ name: String) async throws {}
    func addConnection(name: String, uri: String, identity: String?, makeDefault: Bool) async throws {}
    func replaceConnection(oldName: String, newName: String, uri: String, identity: String?, makeDefault: Bool) async throws {}
    func removeConnection(_ name: String) async throws {}
    func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult {
        ContainerPingResult(engine: .podman, contextName: name, ok: true, latencyMS: 0, summary: "")
    }
}

final class DiagnosticReportServiceTests: XCTestCase {
    private func makeReport(
        docker: StubDockerContextServiceForDiag,
        podman: StubPodmanContextServiceForDiag,
        dockerImage: MockDockerImageServiceForDiag,
        dockerContainer: MockDockerContainerServiceForDiag,
        podmanImage: MockPodmanImageServiceForDiag,
        podmanContainer: MockPodmanContainerServiceForDiag
    ) async -> String {
        let service = DiagnosticReportService(
            dockerService: docker,
            podmanService: podman,
            dockerImageService: dockerImage,
            dockerContainerService: dockerContainer,
            podmanImageService: podmanImage,
            podmanContainerService: podmanContainer
        )
        return await service.makeReport()
    }

    func testReportContainsNewSectionHeaders() async {
        let docker = StubDockerContextServiceForDiag()
        let podman = StubPodmanContextServiceForDiag()
        let dockerImage = MockDockerImageServiceForDiag()
        let dockerContainer = MockDockerContainerServiceForDiag()
        let podmanImage = MockPodmanImageServiceForDiag()
        let podmanContainer = MockPodmanContainerServiceForDiag()

        let report = await makeReport(
            docker: docker,
            podman: podman,
            dockerImage: dockerImage,
            dockerContainer: dockerContainer,
            podmanImage: podmanImage,
            podmanContainer: podmanContainer
        )

        XCTAssertTrue(report.contains("## Container Images (top 20 by size)"))
        XCTAssertTrue(report.contains("## Container Instances (running only)"))
    }

    func testImagesSectionSortedBySizeDesc() async {
        let docker = StubDockerContextServiceForDiag()
        let podman = StubPodmanContextServiceForDiag()
        let dockerImage = MockDockerImageServiceForDiag()
        let dockerContainer = MockDockerContainerServiceForDiag()
        let podmanImage = MockPodmanImageServiceForDiag()
        let podmanContainer = MockPodmanContainerServiceForDiag()

        let now = Date()
        dockerImage.images = [
            ContainerImage(id: "d1", repository: "small", tag: "v1", digest: nil, sizeBytes: 1_000_000, createdAt: now, engine: .docker),
            ContainerImage(id: "d2", repository: "big", tag: "v1", digest: nil, sizeBytes: 500_000_000, createdAt: now, engine: .docker)
        ]
        podmanImage.images = [
            ContainerImage(id: "p1", repository: "mid", tag: "v1", digest: nil, sizeBytes: 100_000_000, createdAt: now, engine: .podman),
            ContainerImage(id: "p2", repository: "huge", tag: "v1", digest: nil, sizeBytes: 900_000_000, createdAt: now, engine: .podman)
        ]

        let report = await makeReport(
            docker: docker,
            podman: podman,
            dockerImage: dockerImage,
            dockerContainer: dockerContainer,
            podmanImage: podmanImage,
            podmanContainer: podmanContainer
        )

        let headerRange = report.range(of: "## Container Images (top 20 by size)")
        XCTAssertNotNil(headerRange)
        let tail = String(report[headerRange!.upperBound...])
        let firstLine = tail.split(whereSeparator: { $0.isNewline })
            .map(String.init)
            .first(where: { $0.hasPrefix("- ") }) ?? ""

        XCTAssertTrue(firstLine.contains("huge:v1"), "expected largest image first, got: \(firstLine)")
        XCTAssertTrue(firstLine.contains("[podman]"))
    }

    func testInstancesSectionFiltersOutExited() async {
        let docker = StubDockerContextServiceForDiag()
        let podman = StubPodmanContextServiceForDiag()
        let dockerImage = MockDockerImageServiceForDiag()
        let dockerContainer = MockDockerContainerServiceForDiag()
        let podmanImage = MockPodmanImageServiceForDiag()
        let podmanContainer = MockPodmanContainerServiceForDiag()

        let now = Date()
        dockerContainer.instances = [
            ContainerInstance(
                id: "r1",
                names: ["web"],
                image: "nginx:latest",
                command: "nginx",
                state: .running,
                status: "Up 5 minutes",
                portsSummary: "",
                createdAt: now,
                engine: .docker
            ),
            ContainerInstance(
                id: "e1",
                names: ["old-worker"],
                image: "busybox:1",
                command: "sh",
                state: .exited,
                status: "Exited (0) 1 hour ago",
                portsSummary: "",
                createdAt: now.addingTimeInterval(-3600),
                engine: .docker
            )
        ]
        podmanContainer.instances = [
            ContainerInstance(
                id: "p-run",
                names: ["cache"],
                image: "redis:7",
                command: "redis-server",
                state: .running,
                status: "Up 2 minutes",
                portsSummary: "",
                createdAt: now.addingTimeInterval(-60),
                engine: .podman
            )
        ]

        let report = await makeReport(
            docker: docker,
            podman: podman,
            dockerImage: dockerImage,
            dockerContainer: dockerContainer,
            podmanImage: podmanImage,
            podmanContainer: podmanContainer
        )

        let headerRange = report.range(of: "## Container Instances (running only)")
        XCTAssertNotNil(headerRange)
        let tail = String(report[headerRange!.upperBound...])
        let section = tail.split(separator: "\n\n", maxSplits: 1).first.map(String.init) ?? tail

        XCTAssertTrue(section.contains("web"))
        XCTAssertTrue(section.contains("cache"))
        XCTAssertFalse(section.contains("old-worker"))
        XCTAssertFalse(section.contains("Exited"))
    }

    func testUnavailableEnginesEmitUnavailableMarker() async {
        let docker = StubDockerContextServiceForDiag()
        docker.available = false
        let podman = StubPodmanContextServiceForDiag()
        podman.available = false
        let dockerImage = MockDockerImageServiceForDiag()
        let dockerContainer = MockDockerContainerServiceForDiag()
        let podmanImage = MockPodmanImageServiceForDiag()
        let podmanContainer = MockPodmanContainerServiceForDiag()

        let report = await makeReport(
            docker: docker,
            podman: podman,
            dockerImage: dockerImage,
            dockerContainer: dockerContainer,
            podmanImage: podmanImage,
            podmanContainer: podmanContainer
        )

        XCTAssertTrue(report.contains("- [docker] _(unavailable)_"))
        XCTAssertTrue(report.contains("- [podman] _(unavailable)_"))
    }
}
