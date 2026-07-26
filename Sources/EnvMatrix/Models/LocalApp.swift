import Foundation

public enum LocalAppSource: Codable, Hashable {
    case appStore
    case brewCask(token: String)
    case other

    private enum CodingKeys: String, CodingKey {
        case type
        case token
    }

    private enum Kind: String, Codable {
        case appStore
        case brewCask
        case other
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .appStore:
            self = .appStore
        case .brewCask:
            let token = try container.decode(String.self, forKey: .token)
            self = .brewCask(token: token)
        case .other:
            self = .other
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .appStore:
            try container.encode(Kind.appStore, forKey: .type)
        case .brewCask(let token):
            try container.encode(Kind.brewCask, forKey: .type)
            try container.encode(token, forKey: .token)
        case .other:
            try container.encode(Kind.other, forKey: .type)
        }
    }
}

public struct LocalApp: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var displayName: String
    public var version: String
    public var bundleId: String
    public var bundlePath: URL
    public var sizeBytes: Int64
    public var source: LocalAppSource
    public var isProtected: Bool
    public var iconPath: URL?

    public init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        version: String,
        bundleId: String,
        bundlePath: URL,
        sizeBytes: Int64,
        source: LocalAppSource,
        isProtected: Bool,
        iconPath: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.version = version
        self.bundleId = bundleId
        self.bundlePath = bundlePath
        self.sizeBytes = sizeBytes
        self.source = source
        self.isProtected = isProtected
        self.iconPath = iconPath
    }
}

public enum LocalAppLeftoverKind: String, Codable, Hashable, CaseIterable {
    case preferences
    case caches
    case appSupport
    case logs
    case savedState
    case containers
    case groupContainers
}

public struct LocalAppLeftover: Identifiable, Codable, Hashable {
    public let id: UUID
    public var url: URL
    public var sizeBytes: Int64
    public var kind: LocalAppLeftoverKind

    public init(
        id: UUID = UUID(),
        url: URL,
        sizeBytes: Int64,
        kind: LocalAppLeftoverKind
    ) {
        self.id = id
        self.url = url
        self.sizeBytes = sizeBytes
        self.kind = kind
    }
}
