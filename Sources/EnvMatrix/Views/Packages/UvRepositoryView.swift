import SwiftUI

public enum UvTab: String, CaseIterable, Identifiable {
    case registry
    case globalTools
    case cache
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .registry: return L("uvRepo.tab.registry")
        case .globalTools: return L("uvRepo.tab.globalTools")
        case .cache: return L("uvRepo.tab.cache")
        }
    }
}

public struct UvRepositoryView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedTab: UvTab = .registry

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker
            Divider()
            Group {
                switch selectedTab {
                case .registry:
                    UvRegistryView()
                case .globalTools:
                    UvGlobalToolsView()
                case .cache:
                    UvCacheView()
                }
            }
        }
        .navigationTitle(L("nav.uvRepo"))
    }

    private var header: some View {
        PageHeader(
            title: L("uvRepo.title"),
            subtitle: L("uvRepo.subtitle"),
            systemImage: NavigationItem.packagesUv.systemImage,
            tint: NavigationItem.packagesUv.tint
        )
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(UvTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
