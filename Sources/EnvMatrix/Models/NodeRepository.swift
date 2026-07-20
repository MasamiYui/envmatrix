import Foundation

/// A named npm registry mirror that can be applied to the user's `.npmrc`.
public struct NodeRegistryMirror: Identifiable, Hashable {
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

/// A globally installed npm package (as reported by `npm ls -g`).
/// Uniqueness is by package name (scoped names allowed).
public struct NodeGlobalPackage: Identifiable, Hashable {
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

/// Aggregated statistics for a local npm cache directory.
public struct NodeCacheStats: Hashable {
    public let path: String
    public let sizeBytes: Int64

    public init(path: String, sizeBytes: Int64) {
        self.path = path
        self.sizeBytes = sizeBytes
    }
}
