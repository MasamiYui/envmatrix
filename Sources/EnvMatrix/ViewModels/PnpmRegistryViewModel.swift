import Foundation

@MainActor
public final class PnpmRegistryViewModel: ObservableObject {
    @Published public var currentRegistry: String = ""
    @Published public var presets: [PnpmRegistryPreset] = []
    @Published public var customURL: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var pnpmAvailable: Bool = true

    private let configService: PnpmConfigService
    private let pnpmService: PnpmService

    public init(configService: PnpmConfigService = DefaultPnpmConfigService(),
                pnpmService: PnpmService = DefaultPnpmService()) {
        self.configService = configService
        self.pnpmService = pnpmService
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.pnpmAvailable = await pnpmService.isAvailable()
        self.presets = configService.presetRegistries()
        do {
            let value = try configService.currentRegistry()
            self.currentRegistry = value
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func applyPreset(_ preset: PnpmRegistryPreset) async {
        await save(preset.url)
    }

    public func applyCustomURL() async {
        let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            self.errorMessage = L("pnpmRepo.msg.invalidURL")
            self.infoMessage = nil
            return
        }
        await save(trimmed)
    }

    private func save(_ value: String) async {
        self.errorMessage = nil
        self.infoMessage = nil
        do {
            try configService.setRegistry(url: value)
            self.currentRegistry = value
            self.customURL = ""
            self.infoMessage = L("pnpmRepo.msg.saved")
            scheduleInfoClear()
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
