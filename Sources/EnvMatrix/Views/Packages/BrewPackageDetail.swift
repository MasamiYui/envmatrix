import SwiftUI

struct BrewPackageDetail: View {
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

struct FlowLayoutHStack: Layout {
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
