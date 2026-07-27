import Foundation

public struct ContainerImage: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let repository: String
    public let tag: String
    public let digest: String?
    public let sizeBytes: Int64
    public let createdAt: Date
    public let engine: ContainerEngine

    public init(
        id: String,
        repository: String,
        tag: String,
        digest: String? = nil,
        sizeBytes: Int64,
        createdAt: Date,
        engine: ContainerEngine
    ) {
        self.id = id
        self.repository = repository
        self.tag = tag
        self.digest = digest
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.engine = engine
    }
}

public enum ContainerImageSort: String, CaseIterable, Sendable, Codable {
    case name
    case size
    case createdAt
}

public struct ImagePruneResult: Hashable, Sendable, Codable {
    public let reclaimedBytes: Int64
    public let rawStdout: String
    public let engine: ContainerEngine

    public init(
        reclaimedBytes: Int64,
        rawStdout: String,
        engine: ContainerEngine
    ) {
        self.reclaimedBytes = reclaimedBytes
        self.rawStdout = rawStdout
        self.engine = engine
    }
}
