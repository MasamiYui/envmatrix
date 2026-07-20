import Foundation

@MainActor
public final class NodeRegistryViewModel: ObservableObject {
    @Published public var currentRegistry: String = ""
    @Published public var presets: [NodeRegistryMirror] = []
    @Published public var customURL: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var npmAvailable: Bool = true

    private let service: NpmrcService
    private let npmService: NpmService

    public init(service: NpmrcService = DefaultNpmrcService(),
                npmService: NpmService = DefaultNpmService()) {
        self.service = service
        self.npmService = npmService
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.npmAvailable = await npmService.isNpmAvailable()
        self.presets = service.presetMirrors()
        do {
            let value = try service.readRegistry()
            self.currentRegistry = value
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func applyPreset(_ mirror: NodeRegistryMirror) async {
        await save(mirror.url)
    }

    public func applyCustomURL() async {
        let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            self.errorMessage = L("nodeRepo.msg.invalidURL")
            self.infoMessage = nil
            return
        }
        await save(trimmed)
    }

    private func save(_ value: String) async {
        self.errorMessage = nil
        self.infoMessage = nil
        do {
            try service.writeRegistry(value)
            self.currentRegistry = value
            self.customURL = ""
            self.infoMessage = L("nodeRepo.msg.saved")
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
