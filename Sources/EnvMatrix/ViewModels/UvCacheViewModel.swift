import Foundation

@MainActor
public final class UvCacheViewModel: ObservableObject {
    @Published public var stats: UvCacheStats? = nil
    @Published public var isLoading: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var showCleanConfirm: Bool = false
    @Published public var uvAvailable: Bool = true

    private let service: UvService

    public init(service: UvService = DefaultUvService()) {
        self.service = service
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.uvAvailable = await service.isAvailable()
        guard uvAvailable else {
            self.stats = nil
            return
        }
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
            self.infoMessage = L("uvRepo.cache.cleaned")
            await load()
            scheduleInfoClear()
            SystemNotifier.shared.notify(
                title: L("notify.uv.cache.title"),
                body: L("notify.uv.cache.body")
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
