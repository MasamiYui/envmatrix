import SwiftUI

public struct DetailView: View {
    let selection: NavigationItem?
    @EnvironmentObject private var localization: LocalizationManager

    public init(selection: NavigationItem?) {
        self.selection = selection
    }

    public var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .dashboard:
            DashboardView()
        case .devEnv(let kind):
            RuntimeDetailView(kind: kind)
                .id(kind)
        case .packagesBrew:
            BrewView()
        case .packagesMaven:
            MavenRepositoryView()
        case .packagesGo:
            GoRepositoryView()
        case .packagesNode:
            NodeRepositoryView()
        case .aiSkills:
            SkillsView()
        case .aiCLI:
            CLIConfigView()
        case .aiMCP:
            MCPServersView()
        case .settings:
            SettingsView()
        case .none:
            WelcomeView()
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.largeTitle.bold())
            Text(L("app.underConstruction"))
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle(title)
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(L("app.welcome.title"))
                .font(.largeTitle.bold())
            Text(L("app.welcome.subtitle"))
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
