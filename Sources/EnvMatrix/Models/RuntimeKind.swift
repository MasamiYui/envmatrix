import Foundation

public enum RuntimeKind: String, CaseIterable, Codable, Identifiable {
    case node
    case python
    case java
    case go
    case rust
    case ruby
    case php
    case deno
    case bun
    case dotnet
    case erlang

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .node: return "Node.js"
        case .python: return "Python"
        case .java: return "Java"
        case .go: return "Go"
        case .rust: return "Rust"
        case .ruby: return "Ruby"
        case .php: return "PHP"
        case .deno: return "Deno"
        case .bun: return "Bun"
        case .dotnet: return ".NET"
        case .erlang: return "Erlang"
        }
    }

    public var binaryName: String {
        switch self {
        case .node: return "node"
        case .python: return "python3"
        case .java: return "java"
        case .go: return "go"
        case .rust: return "rustc"
        case .ruby: return "ruby"
        case .php: return "php"
        case .deno: return "deno"
        case .bun: return "bun"
        case .dotnet: return "dotnet"
        case .erlang: return "erl"
        }
    }
}
