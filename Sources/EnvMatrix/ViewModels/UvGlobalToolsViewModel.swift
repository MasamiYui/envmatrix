import Foundation

@MainActor
public final class UvGlobalToolsViewModel: ObservableObject {
    @Published public var tools: [UvTool] = []
    @Published public var filtered: [UvTool] = []
    @Published public var searchText: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var pendingDelete: UvTool? = nil
    @Published public var uvAvailable: Bool = true

    private let service: UvService

    public init(service: UvService = DefaultUvService()) {
        self.service = service
    }

    public func load() async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }
        self.uvAvailable = await service.isAvailable()
        guard uvAvailable else {
            self.tools = []
            applyFilter()
            return
        }
        do {
            let list = try await service.listGlobalTools()
            self.tools = list
            applyFilter()
        } catch {
            self.errorMessage = error.localizedDescription
            self.tools = []
            applyFilter()
        }
    }

    public func updateSearch(_ text: String) {
        self.searchText = text
        applyFilter()
    }

    public func applyFilter() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [UvTool]
        if q.isEmpty {
            base = tools
        } else {
            base = tools.filter { $0.name.lowercased().contains(q) }
        }
        self.filtered = base.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public func requestDelete(_ tool: UvTool) {
        self.pendingDelete = tool
    }

    public func cancelDelete() {
        self.pendingDelete = nil
    }

    public func confirmDelete() async {
        guard let target = pendingDelete else { return }
        self.pendingDelete = nil
        self.errorMessage = nil
        do {
            try await service.uninstallTool(name: target.name)
            await load()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
