import SwiftUI
import AppKit

public enum RubyTab: String, CaseIterable, Identifiable {
    case source
    case gems
    case cache
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .source: return L("rubyRepo.tab.source")
        case .gems: return L("rubyRepo.tab.gems")
        case .cache: return L("rubyRepo.tab.cache")
        }
    }
}

public struct RubyRepositoryView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedTab: RubyTab = .source

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            PackageRepoHeader(
                title: L("rubyRepo.title"),
                subtitle: L("rubyRepo.subtitle"),
                icon: "diamond.fill",
                color: .red
            )
            HStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(RubyTab.allCases) { tab in
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
            Divider()
            Group {
                switch selectedTab {
                case .source: RubyGemSourceView()
                case .gems: RubyGlobalGemsView()
                case .cache: RubyCacheTabView()
                }
            }
        }
        .navigationTitle(L("nav.rubyRepo"))
    }
}

struct RubyGemSourceView: View {
    @StateObject private var vm = RubyRegistryViewModel()
    @State private var pendingPreset: RubyGemSource? = nil
    @State private var showCustomConfirm: Bool = false

    var body: some View {
        Group {
            if !vm.gemAvailable {
                PackageRepoMissingView(
                    title: L("rubyRepo.gemMissing.title"),
                    subtitle: L("rubyRepo.gemMissing.subtitle")
                )
            } else {
                mainContent
            }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("rubyRepo.source.confirmApply"),
            isPresented: Binding(
                get: { pendingPreset != nil },
                set: { if !$0 { pendingPreset = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("common.confirm")) {
                if let p = pendingPreset {
                    pendingPreset = nil
                    Task { await vm.applyPreset(p) }
                }
            }
            Button(L("common.cancel"), role: .cancel) { pendingPreset = nil }
        } message: {
            if let p = pendingPreset { Text("\(p.name)\n\(p.url)") }
        }
        .confirmationDialog(
            L("rubyRepo.source.confirmApply"),
            isPresented: $showCustomConfirm,
            titleVisibility: .visible
        ) {
            Button(L("common.confirm")) {
                showCustomConfirm = false
                Task { await vm.applyCustomURL() }
            }
            Button(L("common.cancel"), role: .cancel) { showCustomConfirm = false }
        } message: { Text(vm.customURL) }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if let err = vm.errorMessage {
                PackageRepoBanner(text: err, color: .red, icon: "exclamationmark.triangle.fill")
            }
            if let info = vm.infoMessage {
                PackageRepoBanner(text: info, color: .green, icon: "checkmark.circle.fill")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "globe").foregroundStyle(.red)
                        Text(L("rubyRepo.source.current")).bold()
                        Text(vm.currentSource)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            Task { await vm.load() }
                        } label: {
                            Label(L("common.refresh"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(vm.isLoading)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("rubyRepo.source.presets")).font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 8)],
                                  alignment: .leading, spacing: 8) {
                            ForEach(vm.presets) { mirror in
                                Button {
                                    pendingPreset = mirror
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "network")
                                            .foregroundStyle(.red)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(mirror.name).font(.body.bold())
                                            Text(mirror.url)
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer(minLength: 0)
                                        if mirror.url == vm.currentSource {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("rubyRepo.source.custom")).font(.headline)
                        HStack {
                            TextField("https://…", text: $vm.customURL).textFieldStyle(.roundedBorder)
                            Button(L("rubyRepo.source.apply")) { showCustomConfirm = true }
                                .disabled(!isCustomValid)
                        }
                    }
                }
                .padding()
            }
        }
    }

    private var isCustomValid: Bool {
        let t = vm.customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        return t.hasPrefix("http://") || t.hasPrefix("https://")
    }
}

struct RubyGlobalGemsView: View {
    @StateObject private var vm = RubyGlobalGemsViewModel()
    @State private var searchText: String = ""

    var body: some View {
        Group {
            if !vm.gemAvailable {
                PackageRepoMissingView(
                    title: L("rubyRepo.gemMissing.title"),
                    subtitle: L("rubyRepo.gemMissing.subtitle")
                )
            } else {
                mainContent
            }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("rubyRepo.gem.confirmDelete"),
            isPresented: Binding(
                get: { vm.pendingDelete != nil },
                set: { if !$0 { vm.cancelDelete() } }
            ),
            titleVisibility: .visible,
            presenting: vm.pendingDelete
        ) { pkg in
            Button(L("rubyRepo.gem.uninstall"), role: .destructive) {
                Task { await vm.confirmDelete() }
            }
            Button(L("common.cancel"), role: .cancel) { vm.cancelDelete() }
        } message: { pkg in
            Text("\(pkg.name) \(pkg.version)")
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if let err = vm.errorMessage {
                PackageRepoBanner(text: err, color: .red, icon: "exclamationmark.triangle.fill")
            }
            HStack {
                Text(String(format: L("rubyRepo.gem.total"), vm.filtered.count))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await vm.load() }
                } label: {
                    Label(L("common.refresh"), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(vm.isLoading)
            }
            .padding(.horizontal).padding(.top, 8)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("rubyRepo.gem.search"), text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { new in vm.updateSearch(new) }
                if !searchText.isEmpty {
                    Button { searchText = ""; vm.updateSearch("") } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal).padding(.vertical, 8)
            Divider()
            if vm.isLoading {
                VStack(spacing: 12) { ProgressView() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "diamond")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(L("rubyRepo.gem.empty"))
                        .font(.title3.bold()).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(vm.filtered) { pkg in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pkg.name).font(.headline)
                                Text(pkg.version)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { vm.requestDelete(pkg) } label: {
                                Label(L("rubyRepo.gem.uninstall"), systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct RubyCacheTabView: View {
    @StateObject private var vm = RubyCacheViewModel()

    var body: some View {
        Group {
            if !vm.gemAvailable {
                PackageRepoMissingView(
                    title: L("rubyRepo.gemMissing.title"),
                    subtitle: L("rubyRepo.gemMissing.subtitle")
                )
            } else {
                mainContent
            }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("rubyRepo.cache.confirmClean"),
            isPresented: $vm.showCleanConfirm,
            titleVisibility: .visible
        ) {
            Button(L("nodeRepo.cache.clean"), role: .destructive) {
                Task { await vm.confirmClean() }
            }
            Button(L("common.cancel"), role: .cancel) { vm.cancelClean() }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if let err = vm.errorMessage {
                PackageRepoBanner(text: err, color: .red, icon: "exclamationmark.triangle.fill")
            }
            if let info = vm.infoMessage {
                PackageRepoBanner(text: info, color: .green, icon: "checkmark.circle.fill")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()
                        Button {
                            Task { await vm.load() }
                        } label: {
                            Label(L("common.refresh"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(vm.isLoading || vm.isCleaning)
                    }
                    PackageCacheCard<RubyCacheStats>(
                        path: vm.stats?.path ?? "-",
                        size: vm.stats?.sizeBytes,
                        isCleaning: vm.isCleaning,
                        onClean: { vm.requestClean() }
                    )
                }
                .padding()
            }
        }
    }
}
