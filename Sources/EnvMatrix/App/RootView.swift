import SwiftUI

public struct RootView: View {
    @StateObject private var navigator = AppNavigator()
    @AppStorage("colorSchemePreference") private var schemePref: String = "system"
    @StateObject private var localization = LocalizationManager.shared

    /// Persist the split-view state ourselves so a user who accidentally
    /// dragged the sidebar to zero-width doesn't get locked into a
    /// "detail-only" window on next launch.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isSearchPresented: Bool = false

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $navigator.selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
        } detail: {
            DetailView(selection: navigator.selection)
                .navigationSplitViewColumnWidth(min: 500, ideal: 820)
        }
        .navigationSplitViewStyle(.balanced)
        // Total floor: 220 (sidebar) + 500 (detail) + splitter = ~740pt
        // Leaving comfortable padding, we require 820x640 minimum. The window
        // itself opens larger via the WindowGroup default size so users
        // see a well-proportioned layout on first launch.
        .frame(minWidth: 820, minHeight: 640)
        .preferredColorScheme(resolvedScheme)
        .environmentObject(localization)
        .environmentObject(navigator)
        .sheet(isPresented: $isSearchPresented) {
            GlobalSearchView()
                .environmentObject(navigator)
                .environmentObject(localization)
        }
        .onReceive(NotificationCenter.default.publisher(for: .envMatrixOpenGlobalSearch)) { _ in
            isSearchPresented = true
        }
        .onAppear {
            // Guard against SwiftUI restoring a collapsed state from a
            // previous session where the user zero-width'd the sidebar.
            if columnVisibility == .detailOnly {
                columnVisibility = .all
            }
        }
    }

    private var resolvedScheme: ColorScheme? {
        switch schemePref {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
