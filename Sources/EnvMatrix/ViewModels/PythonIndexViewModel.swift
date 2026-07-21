import Foundation

@MainActor
public final class PythonIndexViewModel: ObservableObject {
    @Published public var currentIndex: String = ""
    @Published public var presets: [PythonIndexMirror] = []
    @Published public var customURL: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var pipAvailable: Bool = true

    private let service: PipConfService
    private let pipService: PipService

    public init(service: PipConfService = DefaultPipConfService(),
                pipService: PipService = DefaultPipService()) {
        self.service = service
        self.pipService = pipService
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.pipAvailable = await pipService.isPipAvailable()
        self.presets = service.presetMirrors()
        do {
            let value = try service.readIndexURL()
            self.currentIndex = value
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func applyPreset(_ mirror: PythonIndexMirror) async {
        await save(mirror.url)
    }

    public func applyCustomURL() async {
        let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            self.errorMessage = L("pythonRepo.msg.invalidURL")
            self.infoMessage = nil
            return
        }
        await save(trimmed)
    }

    private func save(_ value: String) async {
        self.errorMessage = nil
        self.infoMessage = nil
        do {
            try service.writeIndexURL(value)
            self.currentIndex = value
            self.customURL = ""
            self.infoMessage = L("pythonRepo.msg.saved")
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
