import Foundation

public enum RuntimeKind: String, CaseIterable, Codable, Identifiable {
    case node
    case python
    case java
    case go
    case rust

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .node: return "Node.js"
        case .python: return "Python"
        case .java: return "Java"
        case .go: return "Go"
        case .rust: return "Rust"
        }
    }

    public var binaryName: String {
        switch self {
        case .node: return "node"
        case .python: return "python3"
        case .java: return "java"
        case .go: return "go"
        case .rust: return "rustc"
        }
    }
}
