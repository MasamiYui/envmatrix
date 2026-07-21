import SwiftUI
import AppKit

public struct InstalledListView: View {
    @ObservedObject var vm: RuntimeViewModel
    @State private var confirmUninstall: RuntimeVersion? = nil
    @State private var managedExpanded: Bool = true
    @State private var systemExpanded: Bool = true

    public init(vm: RuntimeViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Group {
            if vm.installed.isEmpty {
                emptyState
            } else {
                List {
                    if !managedVersions.isEmpty {
                        Section {
                            if managedExpanded {
                                ForEach(managedVersions) { version in
                                    row(for: version)
                                }
                            }
                        } header: {
                            groupHeader(
                                title: L("runtime.group.managed"),
                                count: managedVersions.count,
                                icon: "shippingbox.fill",
                                color: .blue,
                                isExpanded: $managedExpanded
                            )
                        }
                    }
                    if !systemVersions.isEmpty {
                        Section {
                            if systemExpanded {
                                ForEach(systemVersions) { version in
                                    row(for: version)
                                }
                            }
                        } header: {
                            groupHeader(
                                title: L("runtime.group.system"),
                                count: systemVersions.count,
                                icon: "gearshape.2.fill",
                                color: .orange,
                                isExpanded: $systemExpanded
                            )
                        }
                    }
                }
            }
        }
        .alert(
            String(format: L("runtime.uninstallTitle"), confirmUninstall?.version ?? ""),
            isPresented: Binding(
                get: { confirmUninstall != nil },
                set: { newValue in
                    if !newValue { confirmUninstall = nil }
                }
            ),
            presenting: confirmUninstall
        ) { v in
            Button(L("runtime.uninstall"), role: .destructive) {
                Task { await vm.uninstall(v) }
                confirmUninstall = nil
            }
            if v.isSystem, let path = v.installPath?.path {
                Button(L("runtime.revealInFinder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    confirmUninstall = nil
                }
            }
            Button(L("runtime.cancel"), role: .cancel) {
                confirmUninstall = nil
            }
        } message: { v in
            if v.isSystem, let path = v.installPath?.path {
                Text(String(format: L("runtime.uninstallSystemMessage"), path))
            } else {
                Text(String(format: L("runtime.uninstallMessage"), v.kind.displayName, v.version))
            }
        }
    }

    private var managedVersions: [RuntimeVersion] {
        vm.installed.filter { !$0.isSystem }
    }

    private var systemVersions: [RuntimeVersion] {
        vm.installed.filter { $0.isSystem }
    }

    private func groupHeader(
        title: String,
        count: Int,
        icon: String,
        color: Color,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.18), in: Capsule())
                    .foregroundStyle(color)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(L("runtime.noInstalled"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func row(for version: RuntimeVersion) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(version.version)
                        .font(.system(.body, design: .monospaced))
                    if version.isSystem {
                        Text(L("runtime.systemBadge"))
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.25)))
                            .foregroundStyle(.orange)
                    }
                    if vm.activeVersion == version.version {
                        Text(L("runtime.active"))
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.tint))
                            .foregroundStyle(.white)
                    }
                }
                if let path = version.installPath?.path {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button(L("runtime.setActive")) {
                Task { await vm.activate(version) }
            }
            .disabled(vm.activeVersion == version.version)

            Button(role: .destructive) {
                confirmUninstall = version
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(version.isSystem
                  ? L("runtime.uninstallSystemTooltip")
                  : L("runtime.uninstallTooltip"))
        }
        .padding(.vertical, 4)
    }
}
