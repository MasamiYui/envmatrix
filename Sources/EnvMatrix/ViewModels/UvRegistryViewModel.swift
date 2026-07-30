import Foundation

@MainActor
public final class UvRegistryViewModel: ObservableObject {
    @Published public var currentRegistry: String = ""
    @Published public var presets: [UvRegistryPreset] = []
    @Published public var customURL: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var uvAvailable: Bool = true

    private let configService: UvConfigService
    private let uvService: UvService

    public init(configService: UvConfigService = DefaultUvConfigService(),
                uvService: UvService = DefaultUvService()) {
        self.configService = configService
        self.uvService = uvService
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.uvAvailable = await uvService.isAvailable()
        self.presets = configService.presetRegistries()
        do {
            let value = try configService.currentRegistry()
            self.currentRegistry = value
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func applyPreset(_ preset: UvRegistryPreset) async {
        await save(preset.url)
    }

    public func applyCustomURL() async {
        let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            self.errorMessage = L("uvRepo.msg.invalidURL")
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
            self.infoMessage = L("uvRepo.msg.saved")
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
