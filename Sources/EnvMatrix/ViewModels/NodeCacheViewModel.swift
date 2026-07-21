import Foundation

@MainActor
public final class NodeCacheViewModel: ObservableObject {
    @Published public var stats: NodeCacheStats? = nil
    @Published public var isLoading: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var showCleanConfirm: Bool = false
    @Published public var npmAvailable: Bool = true

    private let service: NpmService

    public init(service: NpmService = DefaultNpmService()) {
        self.service = service
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.npmAvailable = await service.isNpmAvailable()
        do {
            let value = try await service.cacheStats()
            self.stats = value
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func requestClean() {
        self.showCleanConfirm = true
    }

    public func cancelClean() {
        self.showCleanConfirm = false
    }

    public func confirmClean() async {
        self.showCleanConfirm = false
        self.isCleaning = true
        self.errorMessage = nil
        self.infoMessage = nil
        defer { self.isCleaning = false }
        do {
            try await service.cacheClean()
            self.infoMessage = L("nodeRepo.cache.cleaned")
            await load()
            scheduleInfoClear()
            NotificationCenter.default.post(
                name: .envMatrixSearchCorpusInvalidated,
                object: SearchHit.Source.node
            )
            SystemNotifier.shared.notify(
                title: L("notify.npm.cache.title"),
                body: L("notify.npm.cache.body")
            )
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func scheduleInfoClear() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                self?.infoMessage = nil
            }
        }
    }
}
