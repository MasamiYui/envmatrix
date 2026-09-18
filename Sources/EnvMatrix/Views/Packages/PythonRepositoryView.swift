import SwiftUI

public enum PythonTab: String, CaseIterable, Identifiable {
    case index
    case globalPkg
    case cache
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .index: return L("pythonRepo.tab.index")
        case .globalPkg: return L("pythonRepo.tab.globalPkg")
        case .cache: return L("pythonRepo.tab.cache")
        }
    }
}

public struct PythonRepositoryView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedTab: PythonTab = .index

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker
            Divider()
            Group {
                switch selectedTab {
                case .index:
                    PythonIndexView()
                case .globalPkg:
                    PythonGlobalPackagesView()
                case .cache:
                    PythonCacheView()
                }
            }
        }
        .navigationTitle(L("nav.pythonRepo"))
    }

    private var header: some View {
        PageHeader(
            title: L("pythonRepo.title"),
            subtitle: L("pythonRepo.subtitle"),
            systemImage: NavigationItem.packagesPython.systemImage,
            tint: NavigationItem.packagesPython.tint
        )
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(PythonTab.allCases) { tab in
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
