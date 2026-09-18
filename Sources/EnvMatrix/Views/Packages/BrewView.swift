import SwiftUI

public struct BrewView: View {
    @StateObject private var vm = BrewViewModel()
    @EnvironmentObject private var localization: LocalizationManager

    public init() {}

    public var body: some View {
        Group {
            if vm.isAvailable {
                mainContent
            } else {
                notInstalledView
            }
        }
        .navigationTitle(L("brew.title"))
        .task { await vm.refreshIfNeeded() }
        .alert(
            String(format: L("brew.uninstall.confirmTitle"), vm.pendingUninstall?.name ?? ""),
            isPresented: Binding(
                get: { vm.pendingUninstall != nil },
                set: { if !$0 { vm.pendingUninstall = nil } }
            ),
            presenting: vm.pendingUninstall
        ) { _ in
            Button(L("brew.action.uninstall"), role: .destructive) {
                Task { await vm.confirmPendingUninstall() }
            }
            Button(L("common.cancel"), role: .cancel) {
                vm.pendingUninstall = nil
            }
        } message: { pkg in
            Text(String(
                format: L(pkg.kind == .cask ? "brew.uninstall.confirmMessage.cask" : "brew.uninstall.confirmMessage.formula"),
                pkg.fullName
            ))
        }
    }

    // MARK: - Not installed placeholder

    private var notInstalledView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(L("brew.notInstalled.title"))
                .font(.title2.bold())
            Text(L("brew.notInstalled.subtitle"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Link(destination: URL(string: "https://brew.sh")!) {
                Label("brew.sh", systemImage: "arrow.up.right.square")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Main layout

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            toolbar
            Divider()
            HSplitView {
                packageList
                    .frame(minWidth: 260, idealWidth: 380)
                detailPane
                    .frame(minWidth: 240)
            }
            if let msg = vm.errorMessage {
                StatusBanner(.error, msg, onDismiss: { vm.errorMessage = nil })
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        PageHeader(
            title: L("brew.title"),
            subtitle: vm.brewVersion,
            systemImage: NavigationItem.packagesBrew.systemImage,
            tint: NavigationItem.packagesBrew.tint,
            isRefreshing: vm.isLoading || vm.runningOperation != nil,
            onRefresh: { Task { await vm.refresh(force: true) } }
        ) {
            if vm.outdatedCount > 0 {
                Label(
                    String(format: L("brew.outdatedCount"), vm.outdatedCount),
                    systemImage: "arrow.up.circle.fill"
                )
                .font(.caption.bold())
                .foregroundStyle(.orange)
            }
            statChip(
                value: vm.formulaeCount,
                label: L("brew.formulae"),
                systemImage: "shippingbox"
            )
            statChip(
                value: vm.casksCount,
                label: L("brew.casks"),
                systemImage: "app.gift"
            )
        }
    }

    private func statChip(value: Int, label: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.callout.monospacedDigit().bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.gray.opacity(0.12)))
    }

    // MARK: - Toolbar (kind picker + search + filters)

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $vm.selectedKind) {
                Text(L("brew.formulae")).tag(BrewPackageKind.formula)
                Text(L("brew.casks")).tag(BrewPackageKind.cask)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L("brew.searchPlaceholder"), text: $vm.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }

            Toggle(L("brew.filter.outdatedOnly"), isOn: $vm.showOnlyOutdated)
                .toggleStyle(.checkbox)

            if vm.selectedKind == .formula {
                Toggle(L("brew.filter.requestedOnly"), isOn: $vm.showOnlyRequested)
                    .toggleStyle(.checkbox)
            }

            Spacer()

            if vm.outdatedCount > 0 {
                Button {
                    Task { await vm.run(.upgradeAll) }
                } label: {
                    Label(L("brew.upgradeAll"), systemImage: "arrow.up.doc.on.clipboard")
                }
                .disabled(vm.runningOperation != nil)
            }

            Menu {
                Button(L("brew.cleanup")) {
                    Task { await vm.run(.cleanup) }
                }
                Button(L("brew.update")) {
                    Task { await vm.run(.update) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(vm.runningOperation != nil)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Package list

    private var packageList: some View {
        Group {
            if vm.isLoading && vm.visiblePackages.isEmpty {
                ProgressView(L("brew.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.visiblePackages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(L("brew.emptyList"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Virtualised list: LazyVStack only realises rows that are
                // scrolled into view. `pkg.id` ("kind:fullName") is stable
                // across refreshes so SwiftUI can reuse row identity when
                // filters change, avoiding a full teardown/rebuild.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(vm.visiblePackages, id: \.id) { pkg in
                            Button {
                                vm.selectedPackageID = pkg.id
                            } label: {
                                HStack {
                                    BrewPackageRow(pkg: pkg)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    vm.selectedPackageID == pkg.id
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.clear
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu { rowContextMenu(pkg) }
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowContextMenu(_ pkg: BrewPackage) -> some View {
        if pkg.isOutdated {
            Button(L("brew.action.upgrade")) {
                Task { await vm.upgrade(pkg) }
            }
        }
        if pkg.kind == .formula {
            Button(pkg.isPinned ? L("brew.action.unpin") : L("brew.action.pin")) {
                Task { await vm.togglePin(pkg) }
            }
        }
        if let home = pkg.homepage, let url = URL(string: home) {
            Divider()
            Link(L("brew.action.openHomepage"), destination: url)
        }
        Divider()
        Button(L("brew.action.uninstall"), role: .destructive) {
            vm.requestUninstall(pkg)
        }
    }

    // MARK: - Detail pane

    private var detailPane: some View {
        Group {
            if let pkg = vm.selectedPackage {
                BrewPackageDetail(pkg: pkg, vm: vm)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.right")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(L("brew.detail.selectHint"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Error banner
}
