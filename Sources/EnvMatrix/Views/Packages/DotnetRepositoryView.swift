import SwiftUI
import AppKit

public enum DotnetTab: String, CaseIterable, Identifiable {
    case source
    case tools
    case cache
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .source: return L("dotnetRepo.tab.source")
        case .tools: return L("dotnetRepo.tab.tools")
        case .cache: return L("dotnetRepo.tab.cache")
        }
    }
}

public struct DotnetRepositoryView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedTab: DotnetTab = .source
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            PackageRepoHeader(
                title: L("dotnetRepo.title"),
                subtitle: L("dotnetRepo.subtitle"),
                icon: "n.circle.fill",
                color: .indigo
            )
            HStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(DotnetTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                Spacer()
            }
            .padding(.horizontal).padding(.bottom, 8)
            Divider()
            Group {
                switch selectedTab {
                case .source: DotnetSourceView()
                case .tools: DotnetGlobalToolsView()
                case .cache: DotnetCacheTabView()
                }
            }
        }
        .navigationTitle(L("nav.dotnetRepo"))
    }
}

struct DotnetSourceView: View {
    @StateObject private var vm = DotnetRegistryViewModel()
    @State private var pendingPreset: NuGetSourceMirror? = nil
    @State private var showCustomConfirm: Bool = false

    var body: some View {
        Group {
            if !vm.dotnetAvailable {
                PackageRepoMissingView(
                    title: L("dotnetRepo.dotnetMissing.title"),
                    subtitle: L("dotnetRepo.dotnetMissing.subtitle")
                )
            } else { mainContent }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("dotnetRepo.source.confirmApply"),
            isPresented: Binding(
                get: { pendingPreset != nil },
                set: { if !$0 { pendingPreset = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("common.confirm")) {
                if let p = pendingPreset { pendingPreset = nil; Task { await vm.applyPreset(p) } }
            }
            Button(L("common.cancel"), role: .cancel) { pendingPreset = nil }
        } message: {
            if let p = pendingPreset { Text("\(p.name)\n\(p.url)") }
        }
        .confirmationDialog(
            L("dotnetRepo.source.confirmApply"),
            isPresented: $showCustomConfirm,
            titleVisibility: .visible
        ) {
            Button(L("common.confirm")) {
                showCustomConfirm = false; Task { await vm.applyCustomURL() }
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
                        Image(systemName: "globe").foregroundStyle(.indigo)
                        Text(L("dotnetRepo.source.enabled")).bold()
                        Spacer()
                        Button {
                            Task { await vm.load() }
                        } label: {
                            Label(L("common.refresh"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(vm.isLoading)
                    }
                    if vm.currentSources.isEmpty {
                        Text(L("dotnetRepo.source.none")).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(vm.currentSources.enumerated()), id: \.offset) { _, item in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    Text(item.name).font(.body.bold())
                                    Text(item.url)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("dotnetRepo.source.presets")).font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 8)],
                                  alignment: .leading, spacing: 8) {
                            ForEach(vm.presets) { mirror in
                                Button { pendingPreset = mirror } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "network").foregroundStyle(.indigo).frame(width: 20)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(mirror.name).font(.body.bold())
                                            Text(mirror.url)
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer(minLength: 0)
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
                        Text(L("dotnetRepo.source.custom")).font(.headline)
                        HStack {
                            TextField(L("dotnetRepo.source.name"), text: $vm.customName)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 180)
                            TextField("https://…", text: $vm.customURL).textFieldStyle(.roundedBorder)
                            Button(L("dotnetRepo.source.apply")) { showCustomConfirm = true }
                                .disabled(!isCustomValid)
                        }
                    }
                    Text(L("dotnetRepo.source.hint"))
                        .font(.caption).foregroundStyle(.secondary)
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

struct DotnetGlobalToolsView: View {
    @StateObject private var vm = DotnetGlobalToolsViewModel()
    @State private var searchText: String = ""

    var body: some View {
        Group {
            if !vm.dotnetAvailable {
                PackageRepoMissingView(
                    title: L("dotnetRepo.dotnetMissing.title"),
                    subtitle: L("dotnetRepo.dotnetMissing.subtitle")
                )
            } else { mainContent }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("dotnetRepo.tool.confirmDelete"),
            isPresented: Binding(
                get: { vm.pendingDelete != nil },
                set: { if !$0 { vm.cancelDelete() } }
            ),
            titleVisibility: .visible,
            presenting: vm.pendingDelete
        ) { tool in
            Button(L("dotnetRepo.tool.uninstall"), role: .destructive) {
                Task { await vm.confirmDelete() }
            }
            Button(L("common.cancel"), role: .cancel) { vm.cancelDelete() }
        } message: { tool in Text("\(tool.name) \(tool.version)") }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if let err = vm.errorMessage {
                PackageRepoBanner(text: err, color: .red, icon: "exclamationmark.triangle.fill")
            }
            HStack {
                Text(String(format: L("dotnetRepo.tool.total"), vm.filtered.count))
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
                TextField(L("dotnetRepo.tool.search"), text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { new in vm.updateSearch(new) }
            }
            .padding(6)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal).padding(.vertical, 8)
            Divider()
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text(L("dotnetRepo.tool.empty")).font(.title3.bold()).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else {
                List {
                    ForEach(vm.filtered) { tool in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tool.name).font(.headline)
                                HStack(spacing: 8) {
                                    Text(tool.version).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                    if let c = tool.commands, !c.isEmpty {
                                        Text(c).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            Button(role: .destructive) { vm.requestDelete(tool) } label: {
                                Label(L("dotnetRepo.tool.uninstall"), systemImage: "trash")
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

struct DotnetCacheTabView: View {
    @StateObject private var vm = DotnetCacheViewModel()

    var body: some View {
        Group {
            if !vm.dotnetAvailable {
                PackageRepoMissingView(
                    title: L("dotnetRepo.dotnetMissing.title"),
                    subtitle: L("dotnetRepo.dotnetMissing.subtitle")
                )
            } else { mainContent }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("dotnetRepo.cache.confirmClean"),
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
                    PackageCacheCard<DotnetCacheStats>(
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
