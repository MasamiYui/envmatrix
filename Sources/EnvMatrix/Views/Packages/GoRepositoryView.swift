import SwiftUI

public enum GoTab: String, CaseIterable, Identifiable {
    case proxy
    case localCache
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .proxy: return L("goRepo.tab.proxy")
        case .localCache: return L("goRepo.tab.localCache")
        }
    }
}

public struct GoRepositoryView: View {
    @StateObject private var proxyVM = GoProxyViewModel()
    @StateObject private var cacheVM = GoLocalCacheViewModel()
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedTab: GoTab = .proxy

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker
            Divider()
            Group {
                switch selectedTab {
                case .proxy:
                    GoProxyView(vm: proxyVM)
                case .localCache:
                    GoLocalCacheView(vm: cacheVM)
                }
            }
        }
        .navigationTitle(L("goRepo.title"))
        .task {
            proxyVM.refresh()
            cacheVM.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "shippingbox.circle")
                .font(.title)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("goRepo.title"))
                    .font(.title2.bold())
                Text(L("goRepo.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                switch selectedTab {
                case .proxy: proxyVM.refresh()
                case .localCache: cacheVM.refresh()
                }
            } label: {
                Label(L("mavenRepo.refresh"), systemImage: "arrow.clockwise")
            }
        }
        .padding()
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(GoTab.allCases) { tab in
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

// MARK: - Proxy tab

struct GoProxyView: View {
    @ObservedObject var vm: GoProxyViewModel

    var body: some View {
        Group {
            if !vm.goAvailable {
                emptyView(
                    icon: "exclamationmark.triangle",
                    title: L("goRepo.goMissing.title"),
                    subtitle: L("goRepo.goMissing.subtitle")
                )
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(L("goRepo.proxy.current"))
                    .bold()
                Text(vm.currentProxy)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Menu(L("goRepo.proxy.applyPreset")) {
                ForEach(vm.presets()) { preset in
                    Button(preset.name) { vm.applyPreset(preset) }
                }
            }
            .fixedSize()

            HStack {
                TextField(L("goRepo.proxy.customPlaceholder"), text: $vm.customValue)
                    .textFieldStyle(.roundedBorder)
                Button(L("goRepo.proxy.save")) {
                    vm.saveCustom()
                }
                .disabled(
                    vm.customValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || vm.isSaving
                )
            }

            if let msg = vm.successMessage {
                Text(msg)
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            if let err = vm.errorMessage {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Spacer()
        }
        .padding()
    }

    private func emptyView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.bold())
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
