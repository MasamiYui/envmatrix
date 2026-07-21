import Foundation

@MainActor
public final class PythonGlobalPackagesViewModel: ObservableObject {
    @Published public var packages: [PythonGlobalPackage] = []
    @Published public var filtered: [PythonGlobalPackage] = []
    @Published public var searchText: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var pendingDelete: PythonGlobalPackage? = nil
    @Published public var pipAvailable: Bool = true

    private let service: PipService

    public init(service: PipService = DefaultPipService()) {
        self.service = service
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.pipAvailable = await service.isPipAvailable()
        guard pipAvailable else {
            self.packages = []
            applyFilter()
            return
        }
        do {
            let list = try await service.listUserPackages()
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
        let base: [PythonGlobalPackage]
        if q.isEmpty {
            base = packages
        } else {
            base = packages.filter { $0.name.lowercased().contains(q) }
        }
        self.filtered = base.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public func requestDelete(_ pkg: PythonGlobalPackage) {
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
            try await service.uninstall(target.name)
            await load()
            NotificationCenter.default.post(
                name: .envMatrixSearchCorpusInvalidated,
                object: SearchHit.Source.python
            )
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
