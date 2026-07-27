import Foundation

@MainActor
public final class ContainerInstancesViewModel: ObservableObject {
    public struct LogsSheetState: Identifiable, Equatable {
        public let id: UUID
        public let instanceID: String
        public let content: String

        public init(instanceID: String, content: String) {
            self.id = UUID()
            self.instanceID = instanceID
            self.content = content
        }
    }

    @Published public var instances: [ContainerInstance] = []
    @Published public var filter: ContainerInstanceFilter = .all
    @Published public var keyword: String = ""
    @Published public var isBusy: Bool = false
    @Published public var errorMessage: String?
    @Published public var isStale: Bool = false
    @Published public var logsSheet: LogsSheetState?

    public let engine: ContainerEngine
    private let dockerService: DockerContainerService?
    private let podmanService: PodmanContainerService?

    public init(
        engine: ContainerEngine,
        dockerService: DockerContainerService? = nil,
        podmanService: PodmanContainerService? = nil
    ) {
        self.engine = engine
        switch engine {
        case .docker:
            self.dockerService = dockerService ?? DefaultDockerContainerService()
            self.podmanService = nil
        case .podman:
            self.dockerService = nil
            self.podmanService = podmanService ?? DefaultPodmanContainerService()
        }
    }

    public var filteredInstances: [ContainerInstance] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let byFilter: [ContainerInstance]
        switch filter {
        case .all:
            byFilter = instances
        case .running:
            byFilter = instances.filter { $0.state == .running }
        case .exited:
            byFilter = instances.filter { $0.state == .exited }
        }
        if trimmed.isEmpty { return byFilter }
        return byFilter.filter { instance in
            if instance.image.lowercased().contains(trimmed) { return true }
            if instance.id.lowercased().contains(trimmed) { return true }
            for name in instance.names where name.lowercased().contains(trimmed) {
                return true
            }
            return false
        }
    }

    public func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        do {
            let list = try await listInstances()
            instances = list
            isStale = false
        } catch {
            errorMessage = Self.describe(error)
        }
        isBusy = false
    }

    public func markStale() {
        isStale = true
    }

    public func start(id: String) async {
        await mutate { [self] in
            switch engine {
            case .docker: try await dockerService?.start(id: id)
            case .podman: try await podmanService?.start(id: id)
            }
        }
    }

    public func stop(id: String) async {
        await mutate { [self] in
            switch engine {
            case .docker: try await dockerService?.stop(id: id)
            case .podman: try await podmanService?.stop(id: id)
            }
        }
    }

    public func restart(id: String) async {
        await mutate { [self] in
            switch engine {
            case .docker: try await dockerService?.restart(id: id)
            case .podman: try await podmanService?.restart(id: id)
            }
        }
    }

    public func remove(id: String) async {
        await mutate { [self] in
            switch engine {
            case .docker: try await dockerService?.remove(id: id)
            case .podman: try await podmanService?.remove(id: id)
            }
        }
    }

    public func viewLogs(id: String, tail: Int = 200) async {
        errorMessage = nil
        do {
            let content = try await fetchLogs(id: id, tail: tail)
            logsSheet = LogsSheetState(instanceID: id, content: content)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    public func inspect(id: String) async -> String? {
        errorMessage = nil
        do {
            switch engine {
            case .docker:
                return try await dockerService?.inspect(id: id)
            case .podman:
                return try await podmanService?.inspect(id: id)
            }
        } catch {
            errorMessage = Self.describe(error)
            return nil
        }
    }

    private func mutate(_ operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        do {
            try await operation()
            let list = try await listInstances()
            instances = list
            isStale = false
        } catch {
            errorMessage = Self.describe(error)
        }
        isBusy = false
    }

    private func listInstances() async throws -> [ContainerInstance] {
        switch engine {
        case .docker:
            guard let service = dockerService else { return [] }
            return try await service.list(all: true)
        case .podman:
            guard let service = podmanService else { return [] }
            return try await service.list(all: true)
        }
    }

    private func fetchLogs(id: String, tail: Int) async throws -> String {
        switch engine {
        case .docker:
            guard let service = dockerService else { return "" }
            return try await service.logs(id: id, tail: tail)
        case .podman:
            guard let service = podmanService else { return "" }
            return try await service.logs(id: id, tail: tail)
        }
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
