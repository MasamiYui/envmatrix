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
        .listStyle(.sidebar)
        // Hard floor: SwiftUI has been observed collapsing the sidebar column
        // below its `.navigationSplitViewColumnWidth(min:)` value when the
        // window is opened at just above the aggregate minimum. Pinning the
        // *view* itself guarantees the column can never render narrower than
        // 220pt regardless of the split-view arithmetic.
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 320)
    }
}
