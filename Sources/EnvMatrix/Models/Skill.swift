import Foundation

public struct Skill: Identifiable, Codable, Hashable {
    public let id: URL
    public let name: String
    public let path: URL
    public var isEnabled: Bool
    public let source: String

    public init(name: String, path: URL, isEnabled: Bool, source: String) {
        self.id = path
        self.name = name
        self.path = path
        self.isEnabled = isEnabled
        self.source = source
    }
}
