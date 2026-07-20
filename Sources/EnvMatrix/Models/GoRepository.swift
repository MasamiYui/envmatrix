import Foundation

/// A cached Go module in the local module cache ($GOPATH/pkg/mod).
/// Each module groups its downloaded versions together for aggregated display.
public struct GoModuleArtifact: Identifiable, Hashable {
    public var id: String { modulePath }
    public let modulePath: String
    public let versions: [GoModuleVersion]
    public let totalSizeBytes: Int64
    public let latestModified: Date?

    public init(
        modulePath: String,
        versions: [GoModuleVersion],
        totalSizeBytes: Int64,
        latestModified: Date?
    ) {
        self.modulePath = modulePath
        self.versions = versions
        self.totalSizeBytes = totalSizeBytes
        self.latestModified = latestModified
    }
}

public struct GoModuleVersion: Identifiable, Hashable {
    public var id: String { path.path }
    public let version: String
    public let sizeBytes: Int64
    public let modifiedAt: Date?
    public let path: URL

    public init(version: String, sizeBytes: Int64, modifiedAt: Date?, path: URL) {
        self.version = version
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.path = path
    }
}

/// A named GOPROXY preset that can be applied to the user's environment.
public struct GoProxyPreset: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let value: String

    public init(id: String, name: String, value: String) {
        self.id = id
        self.name = name
        self.value = value
    }
}
