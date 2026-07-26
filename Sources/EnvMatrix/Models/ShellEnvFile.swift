import Foundation

public enum ShellRcKind: String, CaseIterable, Codable, Identifiable {
    case zshrc
    case zprofile
    case zshenv
    case bashrc
    case bashProfile = "bash_profile"
    case profile

    public var id: String { rawValue }

    public var defaultRelativePath: String {
        switch self {
        case .zshrc: return ".zshrc"
        case .zprofile: return ".zprofile"
        case .zshenv: return ".zshenv"
        case .bashrc: return ".bashrc"
        case .bashProfile: return ".bash_profile"
        case .profile: return ".profile"
        }
    }

    public var displayName: String {
        "~/\(defaultRelativePath)"
    }

    public static func from(shellPath: String) -> ShellRcKind? {
        let name = (shellPath as NSString).lastPathComponent
        switch name {
        case "zsh": return .zshrc
        case "bash": return .bashrc
        default: return nil
        }
    }
}

public struct ShellRcFile: Identifiable, Hashable {
    public let id: String
    public let kind: ShellRcKind
    public let url: URL
    public let exists: Bool
    public let isCurrentShell: Bool

    public init(
        kind: ShellRcKind,
        url: URL,
        exists: Bool,
        isCurrentShell: Bool
    ) {
        self.id = kind.rawValue
        self.kind = kind
        self.url = url
        self.exists = exists
        self.isCurrentShell = isCurrentShell
    }
}

public enum ShellQuoting: String, Codable {
    case none
    case single
    case double
}

public struct ShellVariable: Identifiable, Hashable, Codable {
    public let id: UUID
    public var key: String
    public var value: String
    public var quoting: ShellQuoting
    public var isExported: Bool

    public init(
        id: UUID = UUID(),
        key: String,
        value: String,
        quoting: ShellQuoting,
        isExported: Bool
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.quoting = quoting
        self.isExported = isExported
    }
}

public struct ShellPathAppend: Identifiable, Hashable, Codable {
    public enum Style: String, Codable {
        case doubleQuoted
        case unquoted
    }

    public let id: UUID
    public var segments: [String]
    public var style: Style

    public init(
        id: UUID = UUID(),
        segments: [String],
        style: Style
    ) {
        self.id = id
        self.segments = segments
        self.style = style
    }
}

public enum ShellEnvEntry: Identifiable, Hashable {
    case variable(ShellVariable)
    case pathAppend(ShellPathAppend)
    case unparsed(String)

    public var id: String {
        switch self {
        case .variable(let v): return "var-\(v.id.uuidString)"
        case .pathAppend(let p): return "path-\(p.id.uuidString)"
        case .unparsed(let s): return "raw-\(s.hashValue)"
        }
    }
}

public struct ShellEnvDocument: Hashable {
    public var entries: [ShellEnvEntry]
    public var lineEnding: String
    public var trailingNewline: Bool

    public init(
        entries: [ShellEnvEntry],
        lineEnding: String,
        trailingNewline: Bool
    ) {
        self.entries = entries
        self.lineEnding = lineEnding
        self.trailingNewline = trailingNewline
    }
}
