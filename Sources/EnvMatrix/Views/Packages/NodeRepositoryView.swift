import SwiftUI

public enum NodeTab: String, CaseIterable, Identifiable {
    case registry
    case globalPkg
    case cache
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .registry: return L("nodeRepo.tab.registry")
        case .globalPkg: return L("nodeRepo.tab.globalPkg")
        case .cache: return L("nodeRepo.tab.cache")
        }
    }
}

public struct NodeRepositoryView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedTab: NodeTab = .registry

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker
            Divider()
            Group {
                switch selectedTab {
                case .registry:
                    NodeRegistryView()
                case .globalPkg:
                    NodeGlobalPackagesView()
                case .cache:
                    NodeCacheView()
                }
            }
        }
        .navigationTitle(L("nav.nodeRepo"))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "shippingbox.circle")
                .font(.title)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("nodeRepo.title"))
                    .font(.title2.bold())
                Text(L("nodeRepo.subtitle"))
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
                ForEach(NodeTab.allCases) { tab in
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
