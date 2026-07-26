import SwiftUI
import AppKit

public enum RustTab: String, CaseIterable, Identifiable {
    case registry
    case crates
    case cache
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .registry: return L("rustRepo.tab.registry")
        case .crates: return L("rustRepo.tab.crates")
        case .cache: return L("rustRepo.tab.cache")
        }
    }
}

public struct RustRepositoryView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedTab: RustTab = .registry
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            PackageRepoHeader(
                title: L("rustRepo.title"),
                subtitle: L("rustRepo.subtitle"),
                icon: "shippingbox.circle",
                color: .orange
            )
            HStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(RustTab.allCases) { Text($0.title).tag($0) }
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
                case .registry: RustRegistryTabView()
                case .crates: RustGlobalCratesView()
                case .cache: RustCacheTabView()
                }
            }
        }
        .navigationTitle(L("nav.rustRepo"))
    }
}

struct RustRegistryTabView: View {
    @StateObject private var vm = RustRegistryViewModel()
    @State private var pendingPreset: RustCrateRegistry? = nil
    @State private var showCustomConfirm: Bool = false

    var body: some View {
        Group {
            if !vm.cargoAvailable {
                PackageRepoMissingView(
                    title: L("rustRepo.cargoMissing.title"),
                    subtitle: L("rustRepo.cargoMissing.subtitle")
                )
            } else { mainContent }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("rustRepo.registry.confirmApply"),
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
            L("rustRepo.registry.confirmApply"),
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
                        Image(systemName: "globe").foregroundStyle(.orange)
                        Text(L("rustRepo.registry.current")).bold()
                        Text(vm.currentRegistry)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            Task { await vm.load() }
                        } label: {
                            Label(L("common.refresh"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(vm.isLoading)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("rustRepo.registry.presets")).font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 8)],
                                  alignment: .leading, spacing: 8) {
                            ForEach(vm.presets) { mirror in
                                Button { pendingPreset = mirror } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "network").foregroundStyle(.orange).frame(width: 20)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(mirror.name).font(.body.bold())
                                            Text(mirror.url)
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer(minLength: 0)
                                        if mirror.url == vm.currentRegistry {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
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
                        Text(L("rustRepo.registry.custom")).font(.headline)
                        HStack {
                            TextField("sparse+https://…", text: $vm.customURL).textFieldStyle(.roundedBorder)
                            Button(L("rustRepo.registry.apply")) { showCustomConfirm = true }
                                .disabled(vm.customURL.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    Text(L("rustRepo.registry.hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
    }
}

struct RustGlobalCratesView: View {
    @StateObject private var vm = RustGlobalCratesViewModel()
    @State private var searchText: String = ""

    var body: some View {
        Group {
            if !vm.cargoAvailable {
                PackageRepoMissingView(
                    title: L("rustRepo.cargoMissing.title"),
                    subtitle: L("rustRepo.cargoMissing.subtitle")
                )
            } else { mainContent }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("rustRepo.crate.confirmDelete"),
            isPresented: Binding(
                get: { vm.pendingDelete != nil },
                set: { if !$0 { vm.cancelDelete() } }
            ),
            titleVisibility: .visible,
            presenting: vm.pendingDelete
        ) { pkg in
            Button(L("rustRepo.crate.uninstall"), role: .destructive) {
                Task { await vm.confirmDelete() }
            }
            Button(L("common.cancel"), role: .cancel) { vm.cancelDelete() }
        } message: { pkg in Text("\(pkg.name) \(pkg.version)") }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if let err = vm.errorMessage {
                PackageRepoBanner(text: err, color: .red, icon: "exclamationmark.triangle.fill")
            }
            HStack {
                Text(String(format: L("rustRepo.crate.total"), vm.filtered.count))
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
                TextField(L("rustRepo.crate.search"), text: $searchText)
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
                    Image(systemName: "shippingbox.circle").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text(L("rustRepo.crate.empty"))
                        .font(.title3.bold()).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(vm.filtered) { c in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.name).font(.headline)
                                Text(c.version).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { vm.requestDelete(c) } label: {
                                Label(L("rustRepo.crate.uninstall"), systemImage: "trash")
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

struct RustCacheTabView: View {
    @StateObject private var vm = RustCacheViewModel()

    var body: some View {
        Group {
            if !vm.cargoAvailable {
                PackageRepoMissingView(
                    title: L("rustRepo.cargoMissing.title"),
                    subtitle: L("rustRepo.cargoMissing.subtitle")
                )
            } else { mainContent }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("rustRepo.cache.confirmClean"),
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
                    PackageCacheCard<RustCacheStats>(
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
