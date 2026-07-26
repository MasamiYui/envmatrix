import Foundation

public struct HostsEntry: Identifiable, Hashable, Codable {
    public let id: UUID
    public var isEnabled: Bool
    public var ip: String
    public var hostnames: [String]
    public var comment: String?

    public init(
        id: UUID = UUID(),
        isEnabled: Bool,
        ip: String,
        hostnames: [String],
        comment: String? = nil
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.ip = ip
        self.hostnames = hostnames
        self.comment = comment
    }
}

public enum HostsLine: Identifiable, Hashable {
    case entry(HostsEntry)
    case comment(String)
    case blank
    case unparsed(String)

    public var id: String {
        switch self {
        case .entry(let e): return "entry-\(e.id.uuidString)"
        case .comment(let s): return "comment-\(s.hashValue)"
        case .blank: return "blank-\(UUID().uuidString)"
        case .unparsed(let s): return "raw-\(s.hashValue)"
        }
    }
}

public struct HostsDocument: Hashable {
    public var lines: [HostsLine]
    public var lineEnding: String
    public var trailingNewline: Bool

    public init(
        lines: [HostsLine],
        lineEnding: String,
        trailingNewline: Bool
    ) {
        self.lines = lines
        self.lineEnding = lineEnding
        self.trailingNewline = trailingNewline
    }
}

public struct HostsProfile: Identifiable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var url: URL
    public var isDefault: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.isDefault = isDefault
    }
}

public enum HostsViewMode: String {
    case structured
    case raw
}
