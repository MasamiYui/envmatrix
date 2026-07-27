import Foundation

@MainActor
public final class ContainerImagesViewModel: ObservableObject {
    @Published public var images: [ContainerImage] = []
    @Published public var sort: ContainerImageSort = .name
    @Published public var keyword: String = ""
    @Published public var isBusy: Bool = false
    @Published public var pullLog: [String] = []
    @Published public var errorMessage: String?
    @Published public var isStale: Bool = false

    public private(set) var pullHandle: StreamingHandle?

    public let engine: ContainerEngine
    private let dockerService: DockerImageService?
    private let podmanService: PodmanImageService?

    public init(
        engine: ContainerEngine,
        dockerService: DockerImageService? = nil,
        podmanService: PodmanImageService? = nil
    ) {
        self.engine = engine
        switch engine {
        case .docker:
            self.dockerService = dockerService ?? DefaultDockerImageService()
            self.podmanService = nil
        case .podman:
            self.dockerService = nil
            self.podmanService = podmanService ?? DefaultPodmanImageService()
        }
    }

    public var filteredSortedImages: [ContainerImage] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [ContainerImage]
        if trimmed.isEmpty {
            filtered = images
        } else {
            filtered = images.filter { image in
                image.repository.lowercased().contains(trimmed)
                    || image.tag.lowercased().contains(trimmed)
                    || image.id.lowercased().contains(trimmed)
            }
        }
        switch sort {
        case .name:
            return filtered.sorted { lhs, rhs in
                if lhs.repository == rhs.repository {
                    return lhs.tag < rhs.tag
                }
                return lhs.repository < rhs.repository
            }
        case .size:
            return filtered.sorted { $0.sizeBytes > $1.sizeBytes }
        case .createdAt:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        }
    }

    public func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        do {
            let list = try await listImages()
            images = list
            isStale = false
        } catch {
            errorMessage = Self.describe(error)
        }
        isBusy = false
    }

    public func markStale() {
        isStale = true
    }

    public func pull(reference: String) async {
        guard !isBusy else { return }
        pullLog = []
        isBusy = true
        errorMessage = nil
        let handle: StreamingHandle?
        do {
            handle = try startPull(reference: reference)
        } catch {
            let message = Self.describe(error)
            pullLog.append("error: \(message)")
            errorMessage = message
            isBusy = false
            return
        }
        guard let handle = handle else {
            pullLog.append("error: pull did not start")
            errorMessage = "pull did not start"
            isBusy = false
            return
        }
        pullHandle = handle
        let deadline = Date().addingTimeInterval(30 * 60)
        while handle.isRunning {
            if Date() > deadline {
                handle.cancel()
                pullLog.append("error: pull timed out after 30 minutes")
                break
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            await Task.yield()
        }
        pullHandle = nil
        await refreshInternal()
        isBusy = false
    }

    public func cancelPull() {
        pullHandle?.cancel()
        pullHandle = nil
        pullLog.append("Cancelled")
        isBusy = false
    }

    public func remove(id: String) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        do {
            try await removeImage(id: id)
            await refreshInternal()
        } catch {
            errorMessage = Self.describe(error)
        }
        isBusy = false
    }

    public func tag(source: String, dest: String) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        do {
            try await tagImage(source: source, destination: dest)
            await refreshInternal()
        } catch {
            errorMessage = Self.describe(error)
        }
        isBusy = false
    }

    public func prune(includeUnused: Bool) async -> ImagePruneResult? {
        guard !isBusy else { return nil }
        isBusy = true
        errorMessage = nil
        var pruneResult: ImagePruneResult?
        do {
            pruneResult = try await pruneImages(includeUnused: includeUnused)
            await refreshInternal()
        } catch {
            errorMessage = Self.describe(error)
        }
        isBusy = false
        return pruneResult
    }

    public func inspect(id: String) async -> String? {
        errorMessage = nil
        do {
            return try await inspectImage(id: id)
        } catch {
            errorMessage = Self.describe(error)
            return nil
        }
    }

    private func refreshInternal() async {
        do {
            let list = try await listImages()
            images = list
            isStale = false
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    private func listImages() async throws -> [ContainerImage] {
        switch engine {
        case .docker:
            guard let service = dockerService else { return [] }
            return try await service.list()
        case .podman:
            guard let service = podmanService else { return [] }
            return try await service.list()
        }
    }

    private func startPull(reference: String) throws -> StreamingHandle? {
        let handler: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor [weak self] in
                self?.pullLog.append(line)
            }
        }
        switch engine {
        case .docker:
            guard let service = dockerService else { return nil }
            return try service.pull(reference: reference, onLine: handler)
        case .podman:
            guard let service = podmanService else { return nil }
            return try service.pull(reference: reference, onLine: handler)
        }
    }

    private func removeImage(id: String) async throws {
        switch engine {
        case .docker:
            try await dockerService?.remove(id: id)
        case .podman:
            try await podmanService?.remove(id: id)
        }
    }

    private func tagImage(source: String, destination: String) async throws {
        switch engine {
        case .docker:
            try await dockerService?.tag(source: source, destination: destination)
        case .podman:
            try await podmanService?.tag(source: source, destination: destination)
        }
    }

    private func pruneImages(includeUnused: Bool) async throws -> ImagePruneResult? {
        switch engine {
        case .docker:
            return try await dockerService?.prune(includeUnused: includeUnused)
        case .podman:
            return try await podmanService?.prune(includeUnused: includeUnused)
        }
    }

    private func inspectImage(id: String) async throws -> String? {
        switch engine {
        case .docker:
            return try await dockerService?.inspect(id: id)
        case .podman:
            return try await podmanService?.inspect(id: id)
        }
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
