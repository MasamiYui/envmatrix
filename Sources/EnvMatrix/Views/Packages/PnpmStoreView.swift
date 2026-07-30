import SwiftUI

public struct PnpmStoreView: View {
    @StateObject private var vm = PnpmStoreViewModel()

    public init() {}

    public var body: some View {
        Group {
            if !vm.pnpmAvailable {
                PnpmMissingView()
            } else {
                mainContent
            }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("pnpmRepo.store.confirmPrune"),
            isPresented: $vm.showCleanConfirm,
            titleVisibility: .visible
        ) {
            Button(L("pnpmRepo.store.prune"), role: .destructive) {
                Task { await vm.confirmClean() }
            }
            Button(L("common.cancel"), role: .cancel) {
                vm.cancelClean()
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if let err = vm.errorMessage {
                banner(text: err, color: .red, icon: "exclamationmark.triangle.fill")
            }
            if let info = vm.infoMessage {
                banner(text: info, color: .green, icon: "checkmark.circle.fill")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    toolbar
                    card
                }
                .padding()
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Spacer()
            Button {
                Task { await vm.load() }
            } label: {
                Label(L("common.refresh"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(vm.isLoading || vm.isCleaning)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("pnpmRepo.store.path"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(vm.stats?.path ?? "-")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("pnpmRepo.store.size"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formattedSize)
                        .font(.title3.bold())
                }
                Spacer()
                Button(role: .destructive) {
                    vm.requestClean()
                } label: {
                    Label(L("pnpmRepo.store.prune"), systemImage: "trash")
                }
                .disabled(vm.isCleaning || vm.stats == nil)
            }
            if vm.isCleaning {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(L("pnpmRepo.store.prune"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var formattedSize: String {
        guard let stats = vm.stats else { return "-" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: stats.sizeBytes)
    }

    private func banner(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
            Spacer()
        }
        .padding(8)
        .background(color.opacity(0.08))
    }
}
