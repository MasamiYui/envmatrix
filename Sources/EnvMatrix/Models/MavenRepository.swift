import Foundation

public struct MavenMirror: Identifiable, Codable, Hashable {
    public let id: UUID
    public var mirrorId: String
    public var name: String
    public var url: String
    public var mirrorOf: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        mirrorId: String,
        name: String,
        url: String,
        mirrorOf: String = "central",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.mirrorId = mirrorId
        self.name = name
        self.url = url
        self.mirrorOf = mirrorOf
        self.isEnabled = isEnabled
    }
}

public struct MavenSettings: Codable, Hashable {
    public var localRepository: String?
    public var mirrors: [MavenMirror]

    public init(
        localRepository: String? = nil,
        mirrors: [MavenMirror] = []
    ) {
        self.localRepository = localRepository
        self.mirrors = mirrors
    }
}

/// A downloaded Maven artifact directory in the local repository.
/// Each artifact groups its versions together for aggregated display.
public struct MavenArtifact: Identifiable, Hashable {
    public var id: String { "\(groupId):\(artifactId)" }
    public let groupId: String
    public let artifactId: String
    public let versions: [MavenArtifactVersion]
    public let totalSizeBytes: Int64
    public let latestModified: Date?

    public init(
        groupId: String,
        artifactId: String,
        versions: [MavenArtifactVersion],
        totalSizeBytes: Int64,
        latestModified: Date?
    ) {
        self.groupId = groupId
        self.artifactId = artifactId
        self.versions = versions
        self.totalSizeBytes = totalSizeBytes
        self.latestModified = latestModified
    }
}

public struct MavenArtifactVersion: Identifiable, Hashable {
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

