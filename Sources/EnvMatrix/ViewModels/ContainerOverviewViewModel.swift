import Foundation

@MainActor
public final class ContainerOverviewViewModel: ObservableObject {
    @Published public var dockerContextName: String?
    @Published public var dockerImages: Int = 0
    @Published public var dockerRunning: Int = 0
    @Published public var dockerStopped: Int = 0
    @Published public var podmanConnectionName: String?
    @Published public var podmanImages: Int = 0
    @Published public var podmanRunning: Int = 0
    @Published public var podmanStopped: Int = 0
    @Published public var isLoading: Bool = false

    private let dockerImage: DockerImageService
    private let dockerContainer: DockerContainerService
    private let dockerContext: DockerContextService
    private let podmanImage: PodmanImageService
    private let podmanContainer: PodmanContainerService
    private let podmanContext: PodmanContextService

    public init(
        dockerImage: DockerImageService? = nil,
        dockerContainer: DockerContainerService? = nil,
        dockerContext: DockerContextService? = nil,
        podmanImage: PodmanImageService? = nil,
        podmanContainer: PodmanContainerService? = nil,
        podmanContext: PodmanContextService? = nil
    ) {
        self.dockerImage = dockerImage ?? DefaultDockerImageService()
        self.dockerContainer = dockerContainer ?? DefaultDockerContainerService()
        self.dockerContext = dockerContext ?? DefaultDockerContextService()
        self.podmanImage = podmanImage ?? DefaultPodmanImageService()
        self.podmanContainer = podmanContainer ?? DefaultPodmanContainerService()
        self.podmanContext = podmanContext ?? DefaultPodmanContextService()
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let dockerCtxSvc = dockerContext
        let dockerImgSvc = dockerImage
        let dockerCntSvc = dockerContainer
        let podmanCtxSvc = podmanContext
        let podmanImgSvc = podmanImage
        let podmanCntSvc = podmanContainer

        async let dockerCtxTask: String? = Self.fetchDockerContextName(dockerCtxSvc)
        async let dockerImagesTask: Int = Self.fetchImageCount(dockerImgSvc)
        async let dockerContainersTask: (Int, Int) = Self.fetchContainerCounts(dockerCntSvc)
        async let podmanCtxTask: String? = Self.fetchPodmanConnectionName(podmanCtxSvc)
        async let podmanImagesTask: Int = Self.fetchPodmanImageCount(podmanImgSvc)
        async let podmanContainersTask: (Int, Int) = Self.fetchPodmanContainerCounts(podmanCntSvc)

        let dockerCtx = await dockerCtxTask
        let dockerImagesCount = await dockerImagesTask
        let dockerCounts = await dockerContainersTask
        let podmanCtx = await podmanCtxTask
        let podmanImagesCount = await podmanImagesTask
        let podmanCounts = await podmanContainersTask

        self.dockerContextName = dockerCtx
        self.dockerImages = dockerImagesCount
        self.dockerRunning = dockerCounts.0
        self.dockerStopped = dockerCounts.1
        self.podmanConnectionName = podmanCtx
        self.podmanImages = podmanImagesCount
        self.podmanRunning = podmanCounts.0
        self.podmanStopped = podmanCounts.1
    }

    private static func fetchDockerContextName(_ svc: DockerContextService) async -> String? {
        do {
            let contexts = try await svc.listContexts()
            if let current = contexts.first(where: { $0.isCurrent }) {
                return current.name
            }
            return contexts.first?.name
        } catch {
            return nil
        }
    }

    private static func fetchImageCount(_ svc: DockerImageService) async -> Int {
        do {
            let list = try await svc.list()
            return list.count
        } catch {
            return 0
        }
    }

    private static func fetchContainerCounts(_ svc: DockerContainerService) async -> (Int, Int) {
        do {
            let instances = try await svc.list(all: true)
            let running = instances.filter { $0.state == .running }.count
            let stopped = instances.count - running
            return (running, stopped)
        } catch {
            return (0, 0)
        }
    }

    private static func fetchPodmanConnectionName(_ svc: PodmanContextService) async -> String? {
        do {
            let connections = try await svc.listConnections()
            if let def = connections.first(where: { $0.isDefault }) {
                return def.name
            }
            return connections.first?.name
        } catch {
            return nil
        }
    }

    private static func fetchPodmanImageCount(_ svc: PodmanImageService) async -> Int {
        do {
            let list = try await svc.list()
            return list.count
        } catch {
            return 0
        }
    }

    private static func fetchPodmanContainerCounts(_ svc: PodmanContainerService) async -> (Int, Int) {
        do {
            let instances = try await svc.list(all: true)
            let running = instances.filter { $0.state == .running }.count
            let stopped = instances.count - running
            return (running, stopped)
        } catch {
            return (0, 0)
        }
    }
}
