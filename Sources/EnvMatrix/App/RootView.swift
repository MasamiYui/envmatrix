import SwiftUI

public struct RootView: View {
    @State private var selection: NavigationItem? = .dashboard
    @AppStorage("colorSchemePreference") private var schemePref: String = "system"
    @StateObject private var localization = LocalizationManager.shared

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            DetailView(selection: selection)
        }
        .frame(minWidth: 900, minHeight: 600)
        .preferredColorScheme(resolvedScheme)
        .environmentObject(localization)
    }

    private var resolvedScheme: ColorScheme? {
        switch schemePref {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
