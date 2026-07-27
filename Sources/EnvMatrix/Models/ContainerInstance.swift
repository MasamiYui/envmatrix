import Foundation

public enum ContainerInstanceState: String, Sendable, Codable, Hashable, CaseIterable {
    case running
    case exited
    case paused
    case created
    case restarting
    case dead
    case unknown

    public static func from(_ raw: String) -> ContainerInstanceState {
        ContainerInstanceState(rawValue: raw.lowercased()) ?? .unknown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = ContainerInstanceState.from(raw)
    }
}

public enum ContainerInstanceFilter: String, CaseIterable, Sendable, Codable {
    case all
    case running
    case exited
}

public struct ContainerInstance: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let names: [String]
    public let image: String
    public let command: String
    public let state: ContainerInstanceState
    public let status: String
    public let portsSummary: String
    public let createdAt: Date
    public let engine: ContainerEngine

    public init(
        id: String,
        names: [String],
        image: String,
        command: String,
        state: ContainerInstanceState,
        status: String,
        portsSummary: String,
        createdAt: Date,
        engine: ContainerEngine
    ) {
        self.id = id
        self.names = names
        self.image = image
        self.command = command
        self.state = state
        self.status = status
        self.portsSummary = portsSummary
        self.createdAt = createdAt
        self.engine = engine
    }
}
