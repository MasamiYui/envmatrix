import SwiftUI

public struct SidebarView: View {
    @Binding var selection: NavigationItem?
    @EnvironmentObject private var localization: LocalizationManager

    public init(selection: Binding<NavigationItem?>) {
        self._selection = selection
    }

    public var body: some View {
        List(selection: $selection) {
            ForEach(Array(NavigationItem.allSections.enumerated()), id: \.offset) { _, section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        NavigationLink(value: item) {
                            Label(item.displayName, systemImage: item.systemImage)
                        }
                    }
                }
            }
        }
        .id(localization.language)
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }
}
