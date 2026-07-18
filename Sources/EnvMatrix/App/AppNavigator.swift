import Foundation
import SwiftUI

/// Single source of truth for cross-view navigation.
///
/// Both `SidebarView` (via a two-way binding) and any inner view (via
/// `@EnvironmentObject`) mutate the same `selection` here, so programmatic
/// navigation from a dashboard card automatically updates the sidebar
/// highlight and the detail pane.
@MainActor
public final class AppNavigator: ObservableObject {
    @Published public var selection: NavigationItem?

    public init(initial: NavigationItem? = .dashboard) {
        self.selection = initial
    }

    /// Navigate to an arbitrary item.
    public func select(_ item: NavigationItem) {
        selection = item
    }

    /// Convenience: navigate to the DevEnv detail page of a given runtime.
    public func openRuntime(_ kind: RuntimeKind) {
        selection = .devEnv(kind)
    }
}
