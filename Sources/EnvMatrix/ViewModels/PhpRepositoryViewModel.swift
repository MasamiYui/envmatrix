import Foundation

@MainActor
public final class PhpRegistryViewModel: ObservableObject {
    @Published public var currentRepository: String = ""
    @Published public var presets: [ComposerRepositoryMirror] = []
    @Published public var customURL: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var composerAvailable: Bool = true

    private let service: ComposerService

    public init(service: ComposerService = DefaultComposerService()) { self.service = service }

    public func load() async {
        self.isLoading = true; self.errorMessage = nil
        defer { self.isLoading = false }
        self.composerAvailable = await service.isComposerAvailable()
        self.presets = service.presetMirrors()
        guard composerAvailable else { return }
        do { self.currentRepository = try await service.readRepository() }
        catch { self.errorMessage = error.localizedDescription }
    }

    public func applyPreset(_ mirror: ComposerRepositoryMirror) async { await save(mirror.url) }

    public func applyCustomURL() async {
        let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            self.errorMessage = L("nodeRepo.msg.invalidURL")
            return
        }
        await save(trimmed)
    }

    private func save(_ value: String) async {
        self.errorMessage = nil; self.infoMessage = nil
        do {
            try await service.writeRepository(value)
            self.currentRepository = value
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
public final class PhpGlobalPackagesViewModel: ObservableObject {
    @Published public var packages: [ComposerGlobalPackage] = []
    @Published public var filtered: [ComposerGlobalPackage] = []
    @Published public var searchText: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var pendingDelete: ComposerGlobalPackage? = nil
    @Published public var composerAvailable: Bool = true

    private let service: ComposerService
    public init(service: ComposerService = DefaultComposerService()) { self.service = service }

    public func load() async {
        self.isLoading = true; self.errorMessage = nil
        defer { self.isLoading = false }
        self.composerAvailable = await service.isComposerAvailable()
        guard composerAvailable else { self.packages = []; applyFilter(); return }
        do {
            self.packages = try await service.listGlobalPackages()
            applyFilter()
        } catch {
            self.errorMessage = error.localizedDescription
            self.packages = []; applyFilter()
        }
    }

    public func updateSearch(_ t: String) { self.searchText = t; applyFilter() }

    public func applyFilter() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = q.isEmpty ? packages : packages.filter { $0.name.lowercased().contains(q) }
        self.filtered = base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func requestDelete(_ p: ComposerGlobalPackage) { self.pendingDelete = p }
    public func cancelDelete() { self.pendingDelete = nil }

    public func confirmDelete() async {
        guard let t = pendingDelete else { return }
        self.pendingDelete = nil
        do {
            try await service.uninstallGlobal(t.name)
            await load()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

@MainActor
public final class PhpCacheViewModel: ObservableObject {
    @Published public var stats: ComposerCacheStats? = nil
    @Published public var isLoading: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var infoMessage: String? = nil
    @Published public var showCleanConfirm: Bool = false
    @Published public var composerAvailable: Bool = true

    private let service: ComposerService
    public init(service: ComposerService = DefaultComposerService()) { self.service = service }

    public func load() async {
        self.isLoading = true; self.errorMessage = nil
        defer { self.isLoading = false }
        self.composerAvailable = await service.isComposerAvailable()
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
