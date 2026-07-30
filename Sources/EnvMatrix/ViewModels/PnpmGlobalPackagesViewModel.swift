import Foundation

@MainActor
public final class PnpmGlobalPackagesViewModel: ObservableObject {
    @Published public var packages: [PnpmGlobalPackage] = []
    @Published public var filtered: [PnpmGlobalPackage] = []
    @Published public var searchText: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var pendingDelete: PnpmGlobalPackage? = nil
    @Published public var pnpmAvailable: Bool = true

    private let service: PnpmService

    public init(service: PnpmService = DefaultPnpmService()) {
        self.service = service
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.pnpmAvailable = await service.isAvailable()
        guard pnpmAvailable else {
            self.packages = []
            applyFilter()
            return
        }
        do {
            let list = try await service.listGlobalPackages()
            self.packages = list
            applyFilter()
        } catch {
            self.errorMessage = error.localizedDescription
            self.packages = []
            applyFilter()
        }
    }

    public func updateSearch(_ text: String) {
        self.searchText = text
        applyFilter()
    }

    public func applyFilter() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [PnpmGlobalPackage]
        if q.isEmpty {
            base = packages
        } else {
            base = packages.filter { $0.name.lowercased().contains(q) }
        }
        self.filtered = base.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public func requestDelete(_ pkg: PnpmGlobalPackage) {
        self.pendingDelete = pkg
    }

    public func cancelDelete() {
        self.pendingDelete = nil
    }

    public func confirmDelete() async {
        guard let target = pendingDelete else { return }
        self.pendingDelete = nil
        self.errorMessage = nil
        do {
            try await service.uninstallGlobal(target.name)
            await load()
            NotificationCenter.default.post(
                name: .envMatrixSearchCorpusInvalidated,
                object: SearchHit.Source.node
            )
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
