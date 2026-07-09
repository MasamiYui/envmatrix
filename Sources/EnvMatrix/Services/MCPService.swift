import Foundation

public enum MCPServiceError: Error, LocalizedError {
    case notFound(UUID)
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id): return "MCP server not found: \(id.uuidString)"
        case .invalidJSON(let msg): return "Invalid MCP JSON: \(msg)"
        }
    }
}

public protocol MCPService {
    func list() throws -> [MCPServer]
    func add(_ server: MCPServer) throws
    func update(_ server: MCPServer) throws
    func delete(_ id: UUID) throws
}

public final class DefaultMCPService: MCPService {
    private let configURL: URL
    private let fileManager: FileManager

    public init(
        configURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        if let configURL = configURL {
            self.configURL = configURL
        } else {
            let appSupport = fileManager
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first
                ?? URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Library/Application Support", isDirectory: true)
            self.configURL = appSupport
                .appendingPathComponent("EnvMatrix", isDirectory: true)
                .appendingPathComponent("mcp.json")
        }
        self.fileManager = fileManager
    }

    public func list() throws -> [MCPServer] {
        return try loadServers()
    }

    public func add(_ server: MCPServer) throws {
        var servers = try loadServers()
        servers.append(server)
        try writeServers(servers)
    }

    public func update(_ server: MCPServer) throws {
        var servers = try loadServers()
        guard let idx = servers.firstIndex(where: { $0.id == server.id }) else {
            throw MCPServiceError.notFound(server.id)
        }
        servers[idx] = server
        try writeServers(servers)
    }

    public func delete(_ id: UUID) throws {
        var servers = try loadServers()
        guard let idx = servers.firstIndex(where: { $0.id == id }) else {
            throw MCPServiceError.notFound(id)
        }
        servers.remove(at: idx)
        try writeServers(servers)
    }

    // MARK: - Storage

    private func loadServers() throws -> [MCPServer] {
        if !fileManager.fileExists(atPath: configURL.path) {
            try ensureParentDir()
            try writeServers([])
            return []
        }
        let data = try Data(contentsOf: configURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPServiceError.invalidJSON("root not object")
        }
        guard let rawServers = root["servers"] as? [[String: Any]] else {
            return []
        }
        var out: [MCPServer] = []
        for entry in rawServers {
            guard let idString = entry["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let name = entry["name"] as? String,
                  let command = entry["command"] as? String else {
                continue
            }
            let args = (entry["args"] as? [String]) ?? []
            let env = (entry["env"] as? [String: String]) ?? [:]
            out.append(MCPServer(
                id: id,
                name: name,
                command: command,
                args: args,
                env: env
            ))
        }
        return out
    }

    private func writeServers(_ servers: [MCPServer]) throws {
        try ensureParentDir()
        let payload: [String: Any] = [
            "servers": servers.map { server -> [String: Any] in
                [
                    "id": server.id.uuidString,
                    "name": server.name,
                    "command": server.command,
                    "args": server.args,
                    "env": server.env
                ]
            }
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: configURL, options: .atomic)
    }

    private func ensureParentDir() throws {
        let parent = configURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }
}
