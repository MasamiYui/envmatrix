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
            "Uninstall \(confirmUninstall?.version ?? "")?",
            isPresented: Binding(
                get: { confirmUninstall != nil },
                set: { newValue in
                    if !newValue { confirmUninstall = nil }
                }
            ),
            presenting: confirmUninstall
        ) { v in
            Button("Uninstall", role: .destructive) {
                vm.uninstall(v)
                confirmUninstall = nil
            }
            if v.isSystem, let path = v.installPath?.path {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    confirmUninstall = nil
                }
            }
            Button("Cancel", role: .cancel) {
                confirmUninstall = nil
            }
        } message: { v in
            if v.isSystem, let path = v.installPath?.path {
                Text("EnvMatrix will remove the folder:\n\(path)\n\n"
                     + "If it was installed via brew / sdkman / nvm / pkg, "
                     + "using its own uninstaller is safer. "
                     + "Paths owned by the OS may require sudo and will be rejected.")
            } else {
                Text("This will remove \(v.kind.displayName) \(v.version) from your system.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No installed versions. Switch to Available to install one.")
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
                        Text("System")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.25)))
                            .foregroundStyle(.orange)
                    }
                    if vm.activeVersion == version.version {
                        Text("Active")
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
            Button("Set Active") {
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
                  ? "Uninstall this system runtime (will confirm before deleting)"
                  : "Uninstall this version")
        }
        .padding(.vertical, 4)
    }
}
