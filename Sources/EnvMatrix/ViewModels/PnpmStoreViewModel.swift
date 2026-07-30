import Foundation

@MainActor
public final class PnpmStoreViewModel: ObservableObject {
    @Published public var stats: PnpmStoreStats? = nil
    @Published public var isLoading: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var showCleanConfirm: Bool = false
    @Published public var pnpmAvailable: Bool = true

    private let service: PnpmService

    public init(service: PnpmService = DefaultPnpmService()) {
        self.service = service
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.pnpmAvailable = await service.isAvailable()
        guard pnpmAvailable else {
            self.stats = nil
            return
        }
        do {
            let value = try await service.storeStats()
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
            try await service.storePrune()
            self.infoMessage = L("pnpmRepo.store.pruned")
            await load()
            scheduleInfoClear()
            SystemNotifier.shared.notify(
                title: L("notify.pnpm.store.title"),
                body: L("notify.pnpm.store.body")
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
