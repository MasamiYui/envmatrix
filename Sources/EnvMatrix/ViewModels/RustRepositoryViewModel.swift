import Foundation

@MainActor
public final class RustRegistryViewModel: ObservableObject {
    @Published public var currentRegistry: String = ""
    @Published public var presets: [RustCrateRegistry] = []
    @Published public var customURL: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var cargoAvailable: Bool = true

    private let confService: CargoConfigService
    private let cargoService: CargoService

    public init(confService: CargoConfigService = DefaultCargoConfigService(),
                cargoService: CargoService = DefaultCargoService()) {
        self.confService = confService
        self.cargoService = cargoService
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.cargoAvailable = await cargoService.isCargoAvailable()
        self.presets = confService.presetMirrors()
        do { self.currentRegistry = try confService.readRegistry() }
        catch { self.errorMessage = error.localizedDescription }
    }

    public func applyPreset(_ mirror: RustCrateRegistry) async { await save(mirror.url) }

    public func applyCustomURL() async {
        let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await save(trimmed)
    }

    private func save(_ value: String) async {
        self.errorMessage = nil; self.infoMessage = nil
        do {
            try confService.writeRegistry(value)
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
            await MainActor.run { self?.infoMessage = nil }
        }
    }
}

@MainActor
public final class RustGlobalCratesViewModel: ObservableObject {
    @Published public var crates: [RustGlobalCrate] = []
    @Published public var filtered: [RustGlobalCrate] = []
    @Published public var searchText: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var pendingDelete: RustGlobalCrate? = nil
    @Published public var cargoAvailable: Bool = true

    private let service: CargoService

    public init(service: CargoService = DefaultCargoService()) { self.service = service }

    public func load() async {
        self.isLoading = true; self.errorMessage = nil
        defer { self.isLoading = false }
        self.cargoAvailable = await service.isCargoAvailable()
        guard cargoAvailable else { self.crates = []; applyFilter(); return }
        do {
            self.crates = try await service.listGlobalCrates()
            applyFilter()
        } catch {
            self.errorMessage = error.localizedDescription
            self.crates = []; applyFilter()
        }
    }

    public func updateSearch(_ t: String) { self.searchText = t; applyFilter() }

    public func applyFilter() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = q.isEmpty ? crates : crates.filter { $0.name.lowercased().contains(q) }
        self.filtered = base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func requestDelete(_ c: RustGlobalCrate) { self.pendingDelete = c }
    public func cancelDelete() { self.pendingDelete = nil }

    public func confirmDelete() async {
        guard let t = pendingDelete else { return }
        self.pendingDelete = nil
        do {
            try await service.uninstallCrate(t.name)
            await load()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

@MainActor
public final class RustCacheViewModel: ObservableObject {
    @Published public var stats: RustCacheStats? = nil
    @Published public var isLoading: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var showCleanConfirm: Bool = false
    @Published public var cargoAvailable: Bool = true

    private let service: CargoService

    public init(service: CargoService = DefaultCargoService()) { self.service = service }

    public func load() async {
        self.isLoading = true; self.errorMessage = nil
        defer { self.isLoading = false }
        self.cargoAvailable = await service.isCargoAvailable()
        do { self.stats = try await service.cacheStats() }
        catch { self.errorMessage = error.localizedDescription }
    }

    public func requestClean() { self.showCleanConfirm = true }
    public func cancelClean() { self.showCleanConfirm = false }

    public func confirmClean() async {
        self.showCleanConfirm = false
        self.isCleaning = true
        defer { self.isCleaning = false }
        self.errorMessage = nil; self.infoMessage = nil
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
