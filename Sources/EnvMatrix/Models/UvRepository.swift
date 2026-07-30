import Foundation

public struct UvRegistryPreset: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let url: String
    public let isPreset: Bool
    public init(id: String, name: String, url: String, isPreset: Bool = true) {
        self.id = id; self.name = name; self.url = url; self.isPreset = isPreset
    }
}

public struct UvTool: Identifiable, Hashable, Codable {
    public var id: String { name }
    public let name: String
    public let version: String?
    public init(name: String, version: String? = nil) {
        self.name = name; self.version = version
    }
}

public struct UvCacheStats: Hashable, Codable {
    public let path: String
    public let sizeBytes: Int64
    public init(path: String, sizeBytes: Int64) { self.path = path; self.sizeBytes = sizeBytes }
}
