import SwiftUI
import AppKit

public struct InstalledListView: View {
    @ObservedObject var vm: RuntimeViewModel
    @State private var confirmUninstall: RuntimeVersion? = nil

    public init(vm: RuntimeViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Group {
            if vm.installed.isEmpty {
                emptyState
            } else {
                List(vm.installed) { version in
                    row(for: version)
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
                vm.uninstall(v)
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
                vm.activate(version)
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
