import Foundation

@MainActor
public final class MCPViewModel: ObservableObject {
    @Published public var servers: [MCPServer] = []
    @Published public var editing: MCPServer? = nil
    @Published public var isPresentingEditor: Bool = false
    @Published public var errorMessage: String? = nil

    private let service: MCPService

    public init(service: MCPService = DefaultMCPService()) {
        self.service = service
    }

    public func refresh() {
        do {
            self.servers = try service.list()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func startAdd() {
        self.editing = MCPServer(
            id: UUID(),
            name: "",
            command: "",
            args: [],
            env: [:]
        )
        self.isPresentingEditor = true
    }

    public func startEdit(_ server: MCPServer) {
        self.editing = server
        self.isPresentingEditor = true
    }

    public func save(_ server: MCPServer) {
        do {
            if servers.contains(where: { $0.id == server.id }) {
                try service.update(server)
            } else {
                try service.add(server)
            }
            self.isPresentingEditor = false
            self.editing = nil
            refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func delete(_ server: MCPServer) {
        do {
            try service.delete(server.id)
            refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
