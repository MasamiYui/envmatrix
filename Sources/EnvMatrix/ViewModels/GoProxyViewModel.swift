import Foundation

@MainActor
public final class GoProxyViewModel: ObservableObject {
    @Published public var currentProxy: String = ""
    @Published public var customValue: String = ""
    @Published public var isLoading: Bool = false
    @Published public var isSaving: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var successMessage: String? = nil
    @Published public var goAvailable: Bool = true

    private let service: GoEnvService

    public init(service: GoEnvService = DefaultGoEnvService()) {
        self.service = service
    }

    public func refresh() {
        Task {
            self.isLoading = true
            self.errorMessage = nil
            defer { self.isLoading = false }
            let available = await service.isGoAvailable()
            self.goAvailable = available
            guard available else { return }
            do {
                let value = try await service.readProxy()
                self.currentProxy = value
                self.customValue = value
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public func applyPreset(_ preset: GoProxyPreset) {
        Task { await save(preset.value) }
    }

    public func saveCustom() {
        Task { await save(customValue) }
    }

    private func save(_ value: String) async {
        self.isSaving = true
        self.errorMessage = nil
        defer { self.isSaving = false }
        do {
            try await service.writeProxy(value)
            self.currentProxy = value
            self.customValue = value
            self.successMessage = L("goRepo.proxy.saved")
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    self?.successMessage = nil
                }
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func presets() -> [GoProxyPreset] {
        service.presetProxies()
    }
}
