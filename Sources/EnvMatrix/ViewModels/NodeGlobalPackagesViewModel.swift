import Foundation

@MainActor
public final class NodeGlobalPackagesViewModel: ObservableObject {
    @Published public var packages: [NodeGlobalPackage] = []
    @Published public var filtered: [NodeGlobalPackage] = []
    @Published public var searchText: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var pendingDelete: NodeGlobalPackage? = nil
    @Published public var npmAvailable: Bool = true

    private let service: NpmService

    public init(service: NpmService = DefaultNpmService()) {
        self.service = service
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.npmAvailable = await service.isNpmAvailable()
        guard npmAvailable else {
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
        let base: [NodeGlobalPackage]
        if q.isEmpty {
            base = packages
        } else {
            base = packages.filter { $0.name.lowercased().contains(q) }
        }
        self.filtered = base.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public func requestDelete(_ pkg: NodeGlobalPackage) {
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
