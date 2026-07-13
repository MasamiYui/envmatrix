import Foundation

public enum NavigationItem: Hashable, Identifiable {
    case dashboard
    case devEnv(RuntimeKind)
    case aiSkills
    case aiCLI
    case aiMCP
    case settings

    public var id: String {
        switch self {
        case .dashboard: return "dashboard"
        case .devEnv(let kind): return "devEnv.\(kind.rawValue)"
        case .aiSkills: return "aiSkills"
        case .aiCLI: return "aiCLI"
        case .aiMCP: return "aiMCP"
        case .settings: return "settings"
        }
    }

    public var displayName: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .devEnv(let kind): return kind.displayName
        case .aiSkills: return "Skills"
        case .aiCLI: return "AI CLI"
        case .aiMCP: return "MCP Servers"
        case .settings: return "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .devEnv(let kind):
            switch kind {
            case .node: return "n.square"
            case .python: return "p.square"
            case .java: return "j.square"
            case .go: return "g.square"
            case .rust: return "r.square"
            case .ruby: return "diamond.fill"
            case .php: return "chevron.left.forwardslash.chevron.right"
            case .deno: return "pawprint.fill"
            case .bun: return "leaf.fill"
            case .dotnet: return "n.circle.fill"
            case .erlang: return "antenna.radiowaves.left.and.right"
            }
        case .aiSkills: return "sparkles"
        case .aiCLI: return "terminal"
        case .aiMCP: return "bolt.horizontal"
        case .settings: return "gearshape"
        }
    }
}

extension NavigationItem: CaseIterable {
    public static var allCases: [NavigationItem] {
        var items: [NavigationItem] = [.dashboard]
        items.append(contentsOf: RuntimeKind.allCases.map { .devEnv($0) })
        items.append(contentsOf: [.aiSkills, .aiCLI, .aiMCP, .settings])
        return items
    }
}

public extension NavigationItem {
    static var allSections: [(title: String, items: [NavigationItem])] {
        [
            (title: "Overview", items: [.dashboard]),
            (title: "Dev Environments", items: [
                .devEnv(.node),
                .devEnv(.python),
                .devEnv(.java),
                .devEnv(.go),
                .devEnv(.rust),
                .devEnv(.ruby),
                .devEnv(.php),
                .devEnv(.deno),
                .devEnv(.bun),
                .devEnv(.dotnet),
                .devEnv(.erlang)
            ]),
            (title: "AI Environments", items: [.aiSkills, .aiCLI, .aiMCP]),
            (title: "System", items: [.settings])
        ]
    }
}
