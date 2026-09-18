import SwiftUI
import AppKit

public struct AvailableListView: View {
    @ObservedObject var vm: RuntimeViewModel
    @State private var copiedVersionID: String? = nil

    public init(vm: RuntimeViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Group {
            if vm.isLoadingAvailable {
                ProgressView(L("runtime.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.available.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    if !hasAnyInstallable {
                        manualOnlyNotice
                        Divider()
                    }
                    List(vm.available) { v in
                        row(for: v)
                    }
                }
            }
        }
    }

    private var hasAnyInstallable: Bool {
        vm.available.contains { $0.isInstallable }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(L("runtime.noAvailable"))
                .foregroundStyle(.secondary)
            commandChip(vm.kind.manualInstallCommand, id: "generic")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// Shown when the provider only lists versions and none can be
    /// downloaded by EnvMatrix (rustup, .NET, Erlang, Ruby/PHP source…).
    private var manualOnlyNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            Text(String(format: L("runtime.manualOnly.notice"), vm.kind.displayName))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.06))
    }

    @ViewBuilder
    private func row(for v: RuntimeVersion) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(v.version)
                        .monospaced()
                    if v.isLTS {
                        Text("LTS")
                            .font(.caption)
                            .padding(4)
                            .background(.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                if !v.isInstallable && !isInstalled(v) {
                    Text(L("runtime.manualOnly.hint"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            trailing(for: v)
        }
        .padding(.vertical, 4)
    }

    private func isInstalled(_ v: RuntimeVersion) -> Bool {
        vm.installed.contains(where: { $0.version == v.version })
    }

    @ViewBuilder
    private func trailing(for v: RuntimeVersion) -> some View {
        if vm.installingVersionIDs.contains(v.id) {
            ProgressView(value: vm.installProgress[v.id] ?? 0)
                .frame(width: 120)
        } else if isInstalled(v) {
            Text(L("runtime.installedLabel"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if v.isInstallable {
            Button(L("runtime.install")) {
                Task { await vm.install(v) }
            }
        } else {
            commandChip(vm.kind.manualInstallCommand(version: v.version), id: v.id)
        }
    }

    /// A monospaced command with a copy button, used in place of the
    /// Install button for versions EnvMatrix cannot install itself.
    private func commandChip(_ command: String, id: String) -> some View {
        HStack(spacing: 6) {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: 260, alignment: .trailing)
            Button {
                copy(command, id: id)
            } label: {
                Image(systemName: copiedVersionID == id ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(L("runtime.manualOnly.copy"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func copy(_ text: String, id: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copiedVersionID = id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedVersionID == id { copiedVersionID = nil }
        }
    }
}
