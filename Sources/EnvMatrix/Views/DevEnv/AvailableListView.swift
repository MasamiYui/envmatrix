import SwiftUI

public struct AvailableListView: View {
    @ObservedObject var vm: RuntimeViewModel

    public init(vm: RuntimeViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Group {
            if vm.isLoadingAvailable {
                ProgressView("Loading versions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.available.isEmpty {
                Text("No available versions.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(vm.available) { v in
                    row(for: v)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for v: RuntimeVersion) -> some View {
        HStack {
            Text(v.version)
                .monospaced()
            if v.isLTS {
                Text("LTS")
                    .font(.caption)
                    .padding(4)
                    .background(.green.opacity(0.2))
                    .cornerRadius(4)
            }
            Spacer()
            trailing(for: v)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func trailing(for v: RuntimeVersion) -> some View {
        if vm.installingVersionIDs.contains(v.id) {
            ProgressView(value: vm.installProgress[v.id] ?? 0)
                .frame(width: 120)
        } else if vm.installed.contains(where: { $0.version == v.version }) {
            Text("Installed")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Button("Install") {
                Task { await vm.install(v) }
            }
        }
    }
}
