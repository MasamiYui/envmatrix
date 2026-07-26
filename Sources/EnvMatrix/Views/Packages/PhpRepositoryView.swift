import SwiftUI
import AppKit

public enum PhpTab: String, CaseIterable, Identifiable {
    case repository
    case packages
    case cache
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .repository: return L("phpRepo.tab.repository")
        case .packages: return L("phpRepo.tab.packages")
        case .cache: return L("phpRepo.tab.cache")
        }
    }
}

public struct PhpRepositoryView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedTab: PhpTab = .repository
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            PackageRepoHeader(
                title: L("phpRepo.title"),
                subtitle: L("phpRepo.subtitle"),
                icon: "chevron.left.forwardslash.chevron.right",
                color: .purple
            )
            HStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(PhpTab.allCases) { Text($0.title).tag($0) }
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
                case .repository: PhpRepositoryTabView()
                case .packages: PhpGlobalPackagesTabView()
                case .cache: PhpCacheTabView()
                }
            }
        }
        .navigationTitle(L("nav.phpRepo"))
    }
}

struct PhpRepositoryTabView: View {
    @StateObject private var vm = PhpRegistryViewModel()
    @State private var pendingPreset: ComposerRepositoryMirror? = nil
    @State private var showCustomConfirm: Bool = false

    var body: some View {
        Group {
            if !vm.composerAvailable {
                PackageRepoMissingView(
                    title: L("phpRepo.composerMissing.title"),
                    subtitle: L("phpRepo.composerMissing.subtitle")
                )
            } else { mainContent }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("phpRepo.repository.confirmApply"),
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
            L("phpRepo.repository.confirmApply"),
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
                        Image(systemName: "globe").foregroundStyle(.purple)
                        Text(L("phpRepo.repository.current")).bold()
                        Text(vm.currentRepository)
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
                        Text(L("phpRepo.repository.presets")).font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 8)],
                                  alignment: .leading, spacing: 8) {
                            ForEach(vm.presets) { mirror in
                                Button { pendingPreset = mirror } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "network").foregroundStyle(.purple).frame(width: 20)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(mirror.name).font(.body.bold())
                                            Text(mirror.url)
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer(minLength: 0)
                                        if mirror.url == vm.currentRepository {
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
                        Text(L("phpRepo.repository.custom")).font(.headline)
                        HStack {
                            TextField("https://…", text: $vm.customURL).textFieldStyle(.roundedBorder)
                            Button(L("phpRepo.repository.apply")) { showCustomConfirm = true }
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

struct PhpGlobalPackagesTabView: View {
    @StateObject private var vm = PhpGlobalPackagesViewModel()
    @State private var searchText: String = ""

    var body: some View {
        Group {
            if !vm.composerAvailable {
                PackageRepoMissingView(
                    title: L("phpRepo.composerMissing.title"),
                    subtitle: L("phpRepo.composerMissing.subtitle")
                )
            } else { mainContent }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("phpRepo.pkg.confirmDelete"),
            isPresented: Binding(
                get: { vm.pendingDelete != nil },
                set: { if !$0 { vm.cancelDelete() } }
            ),
            titleVisibility: .visible,
            presenting: vm.pendingDelete
        ) { pkg in
            Button(L("phpRepo.pkg.uninstall"), role: .destructive) {
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
                Text(String(format: L("phpRepo.pkg.total"), vm.filtered.count))
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
                TextField(L("phpRepo.pkg.search"), text: $searchText)
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
                    Image(systemName: "shippingbox").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text(L("phpRepo.pkg.empty")).font(.title3.bold()).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else {
                List {
                    ForEach(vm.filtered) { pkg in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pkg.name).font(.headline)
                                Text(pkg.version).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { vm.requestDelete(pkg) } label: {
                                Label(L("phpRepo.pkg.uninstall"), systemImage: "trash")
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

struct PhpCacheTabView: View {
    @StateObject private var vm = PhpCacheViewModel()

    var body: some View {
        Group {
            if !vm.composerAvailable {
                PackageRepoMissingView(
                    title: L("phpRepo.composerMissing.title"),
                    subtitle: L("phpRepo.composerMissing.subtitle")
                )
            } else { mainContent }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("phpRepo.cache.confirmClean"),
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
                    PackageCacheCard<ComposerCacheStats>(
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
