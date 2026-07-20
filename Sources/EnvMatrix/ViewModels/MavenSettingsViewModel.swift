import Foundation

@MainActor
public final class MavenSettingsViewModel: ObservableObject {
    @Published public var mirrors: [MavenMirror] = []
    @Published public var localRepository: String = ""
    @Published public var errorMessage: String? = nil
    @Published public var settingsPath: String = ""

    private let service: MavenSettingsService

    public init(service: MavenSettingsService = DefaultMavenSettingsService()) {
        self.service = service
        self.settingsPath = service.settingsURL.path
    }

    public func refresh() {
        do {
            let settings = try service.read()
            self.mirrors = settings.mirrors
            self.localRepository = settings.localRepository ?? ""
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func toggleMirror(_ mirror: MavenMirror) {
        guard let idx = mirrors.firstIndex(where: { $0.id == mirror.id }) else { return }
        mirrors[idx].isEnabled.toggle()
        persist()
    }

    public func addMirror(_ mirror: MavenMirror) {
        mirrors.append(mirror)
        persist()
    }

    public func deleteMirror(_ mirror: MavenMirror) {
        mirrors.removeAll { $0.id == mirror.id }
        persist()
    }

    public func applyPreset(_ preset: MavenMirror) {
        if mirrors.contains(where: { $0.mirrorId == preset.mirrorId }) {
            return
        }
        var copy = preset
        copy.isEnabled = true
        mirrors.append(copy)
        persist()
    }

    public func presetMirrors() -> [MavenMirror] {
        service.presetMirrors()
    }

    private func persist() {
        do {
            var settings = try service.read()
            settings.mirrors = mirrors
            if !localRepository.isEmpty {
                settings.localRepository = localRepository
            }
            try service.write(settings)
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
