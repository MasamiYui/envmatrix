import Foundation

public struct MCPServer: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var command: String
    public var args: [String]
    public var env: [String: String]

    public init(
        id: UUID = UUID(),
        name: String,
        command: String,
        args: [String] = [],
        env: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.args = args
        self.env = env
    }
}
