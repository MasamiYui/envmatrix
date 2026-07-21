import Foundation

@MainActor
public final class PythonCacheViewModel: ObservableObject {
    @Published public var stats: PythonCacheStats? = nil
    @Published public var isLoading: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var showCleanConfirm: Bool = false
    @Published public var pipAvailable: Bool = true

    private let service: PipService

    public init(service: PipService = DefaultPipService()) {
        self.service = service
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.pipAvailable = await service.isPipAvailable()
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
            try await service.cachePurge()
            self.infoMessage = L("pythonRepo.cache.cleaned")
            await load()
            scheduleInfoClear()
            NotificationCenter.default.post(
                name: .envMatrixSearchCorpusInvalidated,
                object: SearchHit.Source.python
            )
            SystemNotifier.shared.notify(
                title: L("notify.pip.cache.title"),
                body: L("notify.pip.cache.body")
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
