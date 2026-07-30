import SwiftUI

public enum PnpmTab: String, CaseIterable, Identifiable {
    case registry
    case globalPkg
    case store
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .registry: return L("pnpmRepo.tab.registry")
        case .globalPkg: return L("pnpmRepo.tab.globalPkg")
        case .store: return L("pnpmRepo.tab.store")
        }
    }
}

public struct PnpmRepositoryView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedTab: PnpmTab = .registry

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker
            Divider()
            Group {
                switch selectedTab {
                case .registry:
                    PnpmRegistryView()
                case .globalPkg:
                    PnpmGlobalPackagesView()
                case .store:
                    PnpmStoreView()
                }
            }
        }
        .navigationTitle(L("nav.pnpmRepo"))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "shippingbox.circle")
                .font(.title)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("pnpmRepo.title"))
                    .font(.title2.bold())
                Text(L("pnpmRepo.subtitle"))
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
                ForEach(PnpmTab.allCases) { tab in
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
