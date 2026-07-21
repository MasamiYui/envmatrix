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
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.title)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("pythonRepo.title"))
                    .font(.title2.bold())
                Text(L("pythonRepo.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
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
