import SwiftUI

/// Accent colour for each navigation destination, shared by the sidebar,
/// page headers and dashboard cards so a module looks the same everywhere.
public extension NavigationItem {
    var tint: Color {
        switch self {
        case .dashboard: return .accentColor
        case .devEnv(let kind): return kind.brandColor
        case .packagesBrew: return .orange
        case .packagesMaven: return RuntimeKind.java.brandColor
        case .packagesGo: return RuntimeKind.go.brandColor
        case .packagesNode: return RuntimeKind.node.brandColor
        case .packagesPython: return RuntimeKind.python.brandColor
        case .packagesRuby: return RuntimeKind.ruby.brandColor
        case .packagesRust: return RuntimeKind.rust.brandColor
        case .packagesPhp: return RuntimeKind.php.brandColor
        case .packagesDotnet: return RuntimeKind.dotnet.brandColor
        case .packagesUv: return Color(red: 0.87, green: 0.36, blue: 0.62)   // uv magenta
        case .packagesPnpm: return Color(red: 0.96, green: 0.64, blue: 0.15) // pnpm amber
        case .packagesProjectEnv: return .indigo
        case .aiSkills: return .purple
        case .aiCLI: return .teal
        case .aiMCP: return .orange
        case .systemShellEnv: return .gray
        case .systemHosts: return .blue
        case .systemLocalApps: return .pink
        case .systemContainerContexts: return .cyan
        case .settings: return .gray
        }
    }
}
