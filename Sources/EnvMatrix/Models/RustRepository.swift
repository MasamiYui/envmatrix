import Foundation

public struct RustCrateRegistry: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let url: String
    public let isPreset: Bool

    public init(id: String, name: String, url: String, isPreset: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.isPreset = isPreset
    }
}

public struct RustGlobalCrate: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let version: String
    public let path: String?

    public init(name: String, version: String, path: String? = nil) {
        self.name = name
        self.version = version
        self.path = path
    }
}

public struct RustCacheStats: Hashable {
    public let path: String
    public let sizeBytes: Int64

    public init(path: String, sizeBytes: Int64) {
        self.path = path
        self.sizeBytes = sizeBytes
    }
}
