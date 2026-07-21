import SwiftUI

public struct UsageListView: View {
    @ObservedObject var vm: RuntimeViewModel

    public init(vm: RuntimeViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Group {
            if vm.installed.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    summaryHeader
                    Divider()
                    List(vm.installed) { version in
                        row(for: version)
                    }
                }
            }
        }
    }

    private var summaryHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "internaldrive")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("runtime.usage.total"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if vm.isLoadingUsage && vm.usageByVersionID.isEmpty {
                    Text(L("runtime.usage.loading"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(byteString(vm.totalUsageBytes))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
            }
            Spacer()
            if vm.isLoadingUsage {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await vm.refreshUsage() }
            } label: {
                Label(L("runtime.usage.recompute"), systemImage: "arrow.clockwise")
            }
            .disabled(vm.isLoadingUsage)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "internaldrive")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(L("runtime.usage.empty"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func row(for version: RuntimeVersion) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(version.version)
                        .font(.system(.body, design: .monospaced))
                    tag(for: version)
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
            usageValue(for: version)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func tag(for version: RuntimeVersion) -> some View {
        if version.isSystem {
            Text(L("runtime.usage.system"))
                .font(.caption.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.22)))
                .foregroundStyle(.orange)
        } else {
            Text(L("runtime.usage.managed"))
                .font(.caption.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.blue.opacity(0.20)))
                .foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private func usageValue(for version: RuntimeVersion) -> some View {
        if let bytes = vm.usageByVersionID[version.id] {
            Text(byteString(bytes))
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
        } else if version.installPath == nil {
            Text(L("runtime.usage.unknown"))
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if vm.isLoadingUsage {
            ProgressView()
                .controlSize(.small)
        } else {
            Text("—")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useAll]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
