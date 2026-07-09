import SwiftUI

public struct SidebarView: View {
    @Binding var selection: NavigationItem?

    public init(selection: Binding<NavigationItem?>) {
        self._selection = selection
    }

    public var body: some View {
        List(selection: $selection) {
            ForEach(NavigationItem.allSections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        NavigationLink(value: item) {
                            Label(item.displayName, systemImage: item.systemImage)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }
}
