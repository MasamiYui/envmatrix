import Foundation

@MainActor
public final class DotnetRegistryViewModel: ObservableObject {
    @Published public var currentSources: [(name: String, url: String)] = []
    @Published public var presets: [NuGetSourceMirror] = []
    @Published public var customURL: String = ""
    @Published public var customName: String = "envmatrix-mirror"
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var dotnetAvailable: Bool = true

    private let service: NuGetService

    public init(service: NuGetService = DefaultNuGetService()) { self.service = service }

    public func load() async {
        self.isLoading = true; self.errorMessage = nil
        defer { self.isLoading = false }
        self.dotnetAvailable = await service.isDotnetAvailable()
        self.presets = service.presetMirrors()
        guard dotnetAvailable else { return }
        do { self.currentSources = try await service.readEnabledSources() }
        catch { self.errorMessage = error.localizedDescription }
    }

    public func applyPreset(_ mirror: NuGetSourceMirror) async {
        await save(name: mirror.name, url: mirror.url)
    }

    public func applyCustomURL() async {
        let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            self.errorMessage = L("nodeRepo.msg.invalidURL"); return
        }
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        await save(name: name.isEmpty ? "envmatrix-mirror" : name, url: trimmed)
    }

    private func save(name: String, url: String) async {
        self.errorMessage = nil; self.infoMessage = nil
        do {
            try await service.setPrimarySource(name: name, url: url)
            self.customURL = ""
            self.infoMessage = L("nodeRepo.msg.saved")
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

@MainActor
public final class DotnetGlobalToolsViewModel: ObservableObject {
    @Published public var tools: [DotnetGlobalTool] = []
    @Published public var filtered: [DotnetGlobalTool] = []
    @Published public var searchText: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var pendingDelete: DotnetGlobalTool? = nil
    @Published public var dotnetAvailable: Bool = true

    private let service: NuGetService
    public init(service: NuGetService = DefaultNuGetService()) { self.service = service }

    public func load() async {
        self.isLoading = true; self.errorMessage = nil
        defer { self.isLoading = false }
        self.dotnetAvailable = await service.isDotnetAvailable()
        guard dotnetAvailable else { self.tools = []; applyFilter(); return }
        do {
            self.tools = try await service.listGlobalTools()
            applyFilter()
        } catch {
            self.errorMessage = error.localizedDescription
            self.tools = []; applyFilter()
        }
    }

    public func updateSearch(_ t: String) { self.searchText = t; applyFilter() }

    public func applyFilter() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = q.isEmpty ? tools : tools.filter { $0.name.lowercased().contains(q) }
        self.filtered = base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func requestDelete(_ t: DotnetGlobalTool) { self.pendingDelete = t }
    public func cancelDelete() { self.pendingDelete = nil }

    public func confirmDelete() async {
        guard let t = pendingDelete else { return }
        self.pendingDelete = nil
        do {
            try await service.uninstallGlobalTool(t.name)
            await load()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

@MainActor
public final class DotnetCacheViewModel: ObservableObject {
    @Published public var stats: DotnetCacheStats? = nil
    @Published public var isLoading: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var showCleanConfirm: Bool = false
    @Published public var dotnetAvailable: Bool = true

    private let service: NuGetService
    public init(service: NuGetService = DefaultNuGetService()) { self.service = service }

    public func load() async {
        self.isLoading = true; self.errorMessage = nil
        defer { self.isLoading = false }
        self.dotnetAvailable = await service.isDotnetAvailable()
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
