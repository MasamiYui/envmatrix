import Foundation

public enum ContainerContextsTab: String, CaseIterable, Sendable, Hashable {
    case contexts, images, containers
}

/// Coordinates Docker and Podman context discovery, mutation, and reachability probing for the UI layer.
@MainActor
public final class ContainerContextsViewModel: ObservableObject {
    @Published public var dockerAvailable: Bool = false
    @Published public var podmanAvailable: Bool = false
    @Published public var dockerContexts: [DockerContext] = []
    @Published public var podmanConnections: [PodmanConnection] = []
    @Published public var isDockerBusy: Bool = false
    @Published public var isPodmanBusy: Bool = false
    @Published public var dockerError: String? = nil
    @Published public var podmanError: String? = nil
    @Published public var dockerCollapsed: Bool = false
    @Published public var podmanCollapsed: Bool = false
    @Published public var pingResults: [String: ContainerPingResult] = [:]
    @Published public var podmanNotice: String? = nil
    @Published public var selectedTab: ContainerContextsTab = .contexts

    public let imagesVMDocker: ContainerImagesViewModel
    public let imagesVMPodman: ContainerImagesViewModel
    public let instancesVMDocker: ContainerInstancesViewModel
    public let instancesVMPodman: ContainerInstancesViewModel

    private let dockerService: DockerContextService
    private let podmanService: PodmanContextService

    public init(
        dockerService: DockerContextService = DefaultDockerContextService(),
        podmanService: PodmanContextService = DefaultPodmanContextService(),
        dockerImageService: DockerImageService = DefaultDockerImageService(),
        podmanImageService: PodmanImageService = DefaultPodmanImageService(),
        dockerContainerService: DockerContainerService = DefaultDockerContainerService(),
        podmanContainerService: PodmanContainerService = DefaultPodmanContainerService()
    ) {
        self.dockerService = dockerService
        self.podmanService = podmanService
        self.imagesVMDocker = ContainerImagesViewModel(engine: .docker, dockerService: dockerImageService)
        self.imagesVMPodman = ContainerImagesViewModel(engine: .podman, podmanService: podmanImageService)
        self.instancesVMDocker = ContainerInstancesViewModel(engine: .docker, dockerService: dockerContainerService)
        self.instancesVMPodman = ContainerInstancesViewModel(engine: .podman, podmanService: podmanContainerService)
    }

    public func refresh() async {
        async let d: Void = refreshDocker()
        async let p: Void = refreshPodman()
        _ = await (d, p)
    }

    public func useDocker(_ name: String) async {
        guard !isDockerBusy else { return }
        isDockerBusy = true
        dockerError = nil
        do {
            try await dockerService.useContext(name)
            isDockerBusy = false
            await refreshDocker()
            imagesVMDocker.markStale()
            instancesVMDocker.markStale()
        } catch {
            dockerError = Self.describe(error)
            isDockerBusy = false
        }
    }

    public func createDockerContext(name: String, host: String, description: String?, tls: DockerTLSOptions?) async {
        guard !isDockerBusy else { return }
        isDockerBusy = true
        dockerError = nil
        do {
            try await dockerService.createContext(name: name, host: host, description: description, tls: tls)
            isDockerBusy = false
            await refreshDocker()
        } catch {
            dockerError = Self.describe(error)
            isDockerBusy = false
        }
    }

    public func updateDockerContext(name: String, host: String?, description: String?, tls: DockerTLSOptions?) async {
        guard !isDockerBusy else { return }
        isDockerBusy = true
        dockerError = nil
        do {
            try await dockerService.updateContext(name: name, host: host, description: description, tls: tls)
            isDockerBusy = false
            await refreshDocker()
        } catch {
            dockerError = Self.describe(error)
            isDockerBusy = false
        }
    }

    public func removeDockerContext(_ name: String) async {
        guard !isDockerBusy else { return }
        isDockerBusy = true
        dockerError = nil
        do {
            try await dockerService.removeContext(name)
            isDockerBusy = false
            await refreshDocker()
        } catch {
            dockerError = Self.describe(error)
            isDockerBusy = false
        }
    }

    public func setPodmanDefault(_ name: String) async {
        guard !isPodmanBusy else { return }
        isPodmanBusy = true
        podmanError = nil
        do {
            try await podmanService.setDefault(name)
            isPodmanBusy = false
            await refreshPodman()
            imagesVMPodman.markStale()
            instancesVMPodman.markStale()
        } catch {
            podmanError = Self.describe(error)
            isPodmanBusy = false
        }
    }

    public func addPodmanConnection(name: String, uri: String, identity: String?, makeDefault: Bool) async {
        guard !isPodmanBusy else { return }
        isPodmanBusy = true
        podmanError = nil
        do {
            try await podmanService.addConnection(name: name, uri: uri, identity: identity, makeDefault: makeDefault)
            isPodmanBusy = false
            await refreshPodman()
        } catch {
            podmanError = Self.describe(error)
            isPodmanBusy = false
        }
    }

    public func replacePodmanConnection(oldName: String, newName: String, uri: String, identity: String?, makeDefault: Bool) async {
        guard !isPodmanBusy else { return }
        isPodmanBusy = true
        podmanError = nil
        do {
            try await podmanService.replaceConnection(
                oldName: oldName,
                newName: newName,
                uri: uri,
                identity: identity,
                makeDefault: makeDefault
            )
            isPodmanBusy = false
            await refreshPodman()
        } catch {
            podmanError = Self.describe(error)
            isPodmanBusy = false
        }
    }

    public func removePodmanConnection(_ name: String) async {
        guard !isPodmanBusy else { return }
        isPodmanBusy = true
        podmanError = nil
        let wasDefault = podmanConnections.first(where: { $0.name == name })?.isDefault ?? false
        do {
            try await podmanService.removeConnection(name)
            isPodmanBusy = false
            await refreshPodman()
            if wasDefault, !(podmanConnections.contains(where: { $0.isDefault })) {
                podmanNotice = L("container.podman.defaultInvalidated")
            }
        } catch {
            podmanError = Self.describe(error)
            isPodmanBusy = false
        }
    }

    public func ping(engine: ContainerEngine, name: String, timeout: TimeInterval = 5) async {
        let key = "\(engine.rawValue)/\(name)"
        do {
            let result: ContainerPingResult
            switch engine {
            case .docker:
                result = try await dockerService.ping(name, timeout: timeout)
            case .podman:
                result = try await podmanService.ping(name, timeout: timeout)
            }
            pingResults[key] = result
        } catch {
            pingResults[key] = ContainerPingResult(
                engine: engine,
                contextName: name,
                ok: false,
                latencyMS: 0,
                summary: Self.describe(error),
                rawStderr: ""
            )
        }
    }

    private func refreshDocker() async {
        isDockerBusy = true
        dockerError = nil
        let available = await dockerService.isDockerAvailable()
        dockerAvailable = available
        guard available else {
            dockerContexts = []
            isDockerBusy = false
            return
        }
        do {
            dockerContexts = try await dockerService.listContexts()
        } catch {
            dockerError = Self.describe(error)
            dockerContexts = []
        }
        isDockerBusy = false
    }

    private func refreshPodman() async {
        isPodmanBusy = true
        podmanError = nil
        let available = await podmanService.isPodmanAvailable()
        podmanAvailable = available
        guard available else {
            podmanConnections = []
            isPodmanBusy = false
            return
        }
        do {
            podmanConnections = try await podmanService.listConnections()
        } catch {
            podmanError = Self.describe(error)
            podmanConnections = []
        }
        isPodmanBusy = false
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
