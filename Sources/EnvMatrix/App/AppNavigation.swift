import Foundation

public enum NavigationItem: Hashable, Identifiable {
    case dashboard
    case devEnv(RuntimeKind)
    case packagesBrew
    case packagesMaven
    case aiSkills
    case aiCLI
    case aiMCP
    case settings

    public var id: String {
        switch self {
        case .dashboard: return "dashboard"
        case .devEnv(let kind): return "devEnv.\(kind.rawValue)"
        case .packagesBrew: return "packages.brew"
        case .packagesMaven: return "packages.maven"
        case .aiSkills: return "aiSkills"
        case .aiCLI: return "aiCLI"
        case .aiMCP: return "aiMCP"
        case .settings: return "settings"
        }
    }

    public var displayName: String {
        switch self {
        case .dashboard: return L("nav.dashboard")
        case .devEnv(let kind): return kind.displayName
        case .packagesBrew: return L("nav.homebrew")
        case .packagesMaven: return L("nav.mavenRepo")
        case .aiSkills: return L("nav.skills")
        case .aiCLI: return L("nav.aiCLI")
        case .aiMCP: return L("nav.mcpServers")
        case .settings: return L("nav.settings")
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
        case .packagesBrew: return "cube.box.fill"
        case .packagesMaven: return "shippingbox.fill"
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
        items.append(contentsOf: [.packagesBrew, .packagesMaven, .aiSkills, .aiCLI, .aiMCP, .settings])
        return items
    }
}

public extension NavigationItem {
    static var allSections: [(title: String, items: [NavigationItem])] {
        [
            (title: L("nav.overview"), items: [.dashboard]),
            (title: L("nav.devEnvironments"), items: [
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
            (title: L("nav.packages"), items: [.packagesBrew, .packagesMaven]),
            (title: L("nav.aiEnvironments"), items: [.aiSkills, .aiCLI, .aiMCP]),
            (title: L("nav.system"), items: [.settings])
        ]
    }
}
