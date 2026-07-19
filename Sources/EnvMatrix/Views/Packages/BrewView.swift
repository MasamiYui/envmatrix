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

// MARK: - Row

private struct BrewPackageRow: View {
    let pkg: BrewPackage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: pkg.kind == .cask ? "app.gift.fill" : "shippingbox.fill")
                .foregroundStyle(pkg.kind == .cask ? Color.blue : Color.orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(pkg.name)
                        .font(.headline)
                    if pkg.isOutdated {
                        Text("outdated")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.25)))
                            .foregroundStyle(.orange)
                    }
                    if pkg.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if pkg.isDeprecated {
                        Text("deprecated")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red.opacity(0.2)))
                            .foregroundStyle(.red)
                    }
                    if !pkg.installedOnRequest && pkg.kind == .formula {
                        Text("dep")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .background(Capsule().fill(Color.gray.opacity(0.2)))
                    }
                }
                if let desc = pkg.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let v = pkg.installedVersion {
                        Text(v)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let latest = pkg.latestVersion, pkg.isOutdated {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(latest)
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail pane

private struct BrewPackageDetail: View {
    let pkg: BrewPackage
    @ObservedObject var vm: BrewViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let desc = pkg.description {
                    Text(desc)
                        .foregroundStyle(.secondary)
                }
                Divider()
                metadataSection
                if pkg.kind == .formula && !pkg.dependencies.isEmpty {
                    Divider()
                    dependenciesSection
                }
                Divider()
                actionsSection
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: pkg.kind == .cask ? "app.gift.fill" : "shippingbox.fill")
                .font(.title)
                .foregroundStyle(pkg.kind == .cask ? Color.blue : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(pkg.name).font(.title2.bold())
                Text(pkg.fullName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(label: L("brew.detail.kind"), value: pkg.kind.rawValue.capitalized)
            if let v = pkg.installedVersion {
                row(label: L("brew.detail.installedVersion"), value: v)
            }
            if let latest = pkg.latestVersion, pkg.isOutdated {
                row(label: L("brew.detail.latestVersion"), value: latest, valueColor: .orange)
            }
            if let home = pkg.homepage {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("brew.detail.homepage")).font(.caption).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                    if let url = URL(string: home) {
                        Link(home, destination: url).font(.caption)
                    } else {
                        Text(home).font(.caption)
                    }
                }
            }
            if pkg.kind == .cask {
                row(label: L("brew.detail.autoUpdates"), value: pkg.autoUpdates ? L("brew.yes") : L("brew.no"))
                if let at = pkg.installedAt {
                    row(label: L("brew.detail.installedAt"), value: at.formatted(date: .abbreviated, time: .shortened))
                }
            }
            if pkg.isDeprecated, let reason = pkg.deprecationReason {
                row(label: L("brew.detail.deprecationReason"), value: reason, valueColor: .red)
            }
        }
    }

    private var dependenciesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("brew.detail.dependencies"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            FlowLayoutHStack(spacing: 6) {
                ForEach(pkg.dependencies, id: \.self) { dep in
                    Text(dep)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.gray.opacity(0.18)))
                }
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: 8) {
            if pkg.isOutdated {
                Button {
                    Task { await vm.upgrade(pkg) }
                } label: {
                    Label(L("brew.action.upgrade"), systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.runningOperation != nil)
            }
            if pkg.kind == .formula {
                Button {
                    Task { await vm.togglePin(pkg) }
                } label: {
                    Label(
                        pkg.isPinned ? L("brew.action.unpin") : L("brew.action.pin"),
                        systemImage: pkg.isPinned ? "pin.slash" : "pin"
                    )
                }
                .disabled(vm.runningOperation != nil)
            }
            Spacer()
            Button(role: .destructive) {
                Task { await vm.uninstall(pkg) }
            } label: {
                Label(L("brew.action.uninstall"), systemImage: "trash")
            }
            .disabled(vm.runningOperation != nil)
        }
    }

    private func row(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - Minimal flow layout for tag chips

/// A tiny SwiftUI Layout that flows children left-to-right and wraps to a
/// new row when width is exceeded. Simpler than pulling in a dependency.
private struct FlowLayoutHStack: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        for s in sizes {
            if lineWidth + s.width > maxWidth, lineWidth > 0 {
                totalHeight += lineHeight + spacing
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
        totalHeight += lineHeight
        return CGSize(width: maxWidth == .infinity ? lineWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for (i, s) in sizes.enumerated() {
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}
