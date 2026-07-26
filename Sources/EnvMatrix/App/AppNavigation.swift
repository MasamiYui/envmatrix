import Foundation

public enum NavigationItem: Hashable, Identifiable {
    case dashboard
    case devEnv(RuntimeKind)
    case packagesBrew
    case packagesMaven
    case packagesGo
    case packagesNode
    case packagesPython
    case packagesRuby
    case packagesRust
    case packagesPhp
    case packagesDotnet
    case packagesProjectEnv
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
        case .packagesGo: return "packages.go"
        case .packagesNode: return "packages.node"
        case .packagesPython: return "packages.python"
        case .packagesRuby: return "packages.ruby"
        case .packagesRust: return "packages.rust"
        case .packagesPhp: return "packages.php"
        case .packagesDotnet: return "packages.dotnet"
        case .packagesProjectEnv: return "packages.projectEnv"
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
        case .packagesGo: return L("nav.goRepo")
        case .packagesNode: return L("nav.nodeRepo")
        case .packagesPython: return L("nav.pythonRepo")
        case .packagesRuby: return L("nav.rubyRepo")
        case .packagesRust: return L("nav.rustRepo")
        case .packagesPhp: return L("nav.phpRepo")
        case .packagesDotnet: return L("nav.dotnetRepo")
        case .packagesProjectEnv: return L("nav.projectEnv")
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
        case .packagesGo: return "shippingbox.fill"
        case .packagesNode: return "shippingbox.fill"
        case .packagesPython: return "shippingbox.fill"
        case .packagesRuby: return "shippingbox.fill"
        case .packagesRust: return "shippingbox.fill"
        case .packagesPhp: return "shippingbox.fill"
        case .packagesDotnet: return "shippingbox.fill"
        case .packagesProjectEnv: return "folder.badge.gearshape"
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
        items.append(contentsOf: [.packagesBrew, .packagesMaven, .packagesGo, .packagesNode, .packagesPython, .packagesRuby, .packagesRust, .packagesPhp, .packagesDotnet, .packagesProjectEnv, .aiSkills, .aiCLI, .aiMCP, .settings])
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
            (title: L("nav.packagesSystem"), items: [.packagesBrew]),
            (title: L("nav.packagesLangs"), items: [.packagesMaven, .packagesGo, .packagesNode, .packagesPython, .packagesRuby, .packagesRust, .packagesPhp, .packagesDotnet]),
            (title: L("nav.projectEnvGroup"), items: [.packagesProjectEnv]),
            (title: L("nav.aiEnvironments"), items: [.aiSkills, .aiCLI, .aiMCP]),
            (title: L("nav.system"), items: [.settings])
        ]
    }
}
