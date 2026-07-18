import SwiftUI

public struct RootView: View {
    @StateObject private var navigator = AppNavigator()
    @AppStorage("colorSchemePreference") private var schemePref: String = "system"
    @StateObject private var localization = LocalizationManager.shared

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(selection: $navigator.selection)
        } detail: {
            DetailView(selection: navigator.selection)
        }
        .frame(minWidth: 900, minHeight: 600)
        .preferredColorScheme(resolvedScheme)
        .environmentObject(localization)
        .environmentObject(navigator)
    }

    private var resolvedScheme: ColorScheme? {
        switch schemePref {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
