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
                errorBanner(msg)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "cube.box.fill")
                .font(.title)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("brew.title"))
                    .font(.title2.bold())
                HStack(spacing: 6) {
                    if !vm.brewVersion.isEmpty {
                        Text(vm.brewVersion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if vm.outdatedCount > 0 {
                        Label(
                            String(format: L("brew.outdatedCount"), vm.outdatedCount),
                            systemImage: "arrow.up.circle.fill"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()

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

            if vm.runningOperation != nil {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await vm.refresh(force: true) }
                } label: {
                    Label(L("brew.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(vm.isLoading)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
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
                List(vm.visiblePackages, selection: $vm.selectedPackageID) { pkg in
                    BrewPackageRow(pkg: pkg)
                        .tag(pkg.id)
                        .contextMenu { rowContextMenu(pkg) }
                }
                .listStyle(.inset)
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
            Task { await vm.uninstall(pkg) }
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

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(msg)
                .font(.callout)
                .lineLimit(3)
            Spacer()
            Button {
                vm.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }
}
