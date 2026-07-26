import Foundation

public struct NuGetSourceMirror: Identifiable, Hashable {
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

public struct DotnetGlobalTool: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let version: String
    public let commands: String?

    public init(name: String, version: String, commands: String? = nil) {
        self.name = name
        self.version = version
        self.commands = commands
    }
}

public struct DotnetCacheStats: Hashable {
    public let path: String
    public let sizeBytes: Int64

    public init(path: String, sizeBytes: Int64) {
        self.path = path
        self.sizeBytes = sizeBytes
    }
}
