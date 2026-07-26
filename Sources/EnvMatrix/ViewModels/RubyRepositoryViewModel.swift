import Foundation

@MainActor
public final class RubyRegistryViewModel: ObservableObject {
    @Published public var currentSource: String = ""
    @Published public var presets: [RubyGemSource] = []
    @Published public var customURL: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var gemAvailable: Bool = true

    private let confService: GemConfigService
    private let gemService: GemService

    public init(confService: GemConfigService = DefaultGemConfigService(),
                gemService: GemService = DefaultGemService()) {
        self.confService = confService
        self.gemService = gemService
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.gemAvailable = await gemService.isGemAvailable()
        self.presets = confService.presetMirrors()
        do {
            self.currentSource = try confService.readSource()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func applyPreset(_ mirror: RubyGemSource) async {
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
            try confService.writeSource(value)
            self.currentSource = value
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
            await MainActor.run { self?.infoMessage = nil }
        }
    }
}

@MainActor
public final class RubyGlobalGemsViewModel: ObservableObject {
    @Published public var gems: [RubyGlobalGem] = []
    @Published public var filtered: [RubyGlobalGem] = []
    @Published public var searchText: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var pendingDelete: RubyGlobalGem? = nil
    @Published public var gemAvailable: Bool = true

    private let service: GemService

    public init(service: GemService = DefaultGemService()) {
        self.service = service
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.gemAvailable = await service.isGemAvailable()
        guard gemAvailable else { self.gems = []; applyFilter(); return }
        do {
            self.gems = try await service.listGlobalGems()
            applyFilter()
        } catch {
            self.errorMessage = error.localizedDescription
            self.gems = []; applyFilter()
        }
    }

    public func updateSearch(_ text: String) { self.searchText = text; applyFilter() }

    public func applyFilter() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = q.isEmpty ? gems : gems.filter { $0.name.lowercased().contains(q) }
        self.filtered = base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func requestDelete(_ pkg: RubyGlobalGem) { self.pendingDelete = pkg }
    public func cancelDelete() { self.pendingDelete = nil }

    public func confirmDelete() async {
        guard let target = pendingDelete else { return }
        self.pendingDelete = nil
        self.errorMessage = nil
        do {
            try await service.uninstallGem(target.name)
            await load()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

@MainActor
public final class RubyCacheViewModel: ObservableObject {
    @Published public var stats: RubyCacheStats? = nil
    @Published public var isLoading: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var showCleanConfirm: Bool = false
    @Published public var gemAvailable: Bool = true

    private let service: GemService

    public init(service: GemService = DefaultGemService()) { self.service = service }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.gemAvailable = await service.isGemAvailable()
        do { self.stats = try await service.cacheStats() }
        catch { self.errorMessage = error.localizedDescription }
    }

    public func requestClean() { self.showCleanConfirm = true }
    public func cancelClean() { self.showCleanConfirm = false }

    public func confirmClean() async {
        self.showCleanConfirm = false
        self.isCleaning = true
        self.errorMessage = nil; self.infoMessage = nil
        defer { self.isCleaning = false }
        do {
            try await service.cacheClean()
            self.infoMessage = L("nodeRepo.cache.cleaned")
            await load()
            scheduleInfoClear()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func scheduleInfoClear() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { self?.infoMessage = nil }
        }
    }
}
