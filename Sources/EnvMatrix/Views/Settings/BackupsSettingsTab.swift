import SwiftUI
import AppKit

struct BackupsSettingsTab: View {
    @StateObject private var vm = BackupsViewModel()

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            banners
            if vm.entries.isEmpty && !vm.isLoading {
                emptyState
            } else {
                list
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await vm.load() }
        .confirmationDialog(
            confirmRestoreMessage,
            isPresented: Binding(
                get: { vm.pendingRestore != nil },
                set: { newValue in if !newValue { vm.cancelRestore() } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("settings.backups.restore")) {
                Task { await vm.confirmRestore() }
            }
            Button(L("common.cancel"), role: .cancel) {
                vm.cancelRestore()
            }
        }
        .confirmationDialog(
            L("settings.backups.confirmDelete"),
            isPresented: Binding(
                get: { vm.pendingDelete != nil },
                set: { newValue in if !newValue { vm.cancelDelete() } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("settings.backups.delete"), role: .destructive) {
                Task { await vm.confirmDelete() }
            }
            Button(L("common.cancel"), role: .cancel) {
                vm.cancelDelete()
            }
        }
    }

    private var confirmRestoreMessage: String {
        if let entry = vm.pendingRestore {
            return String(format: L("settings.backups.confirmRestore"), entry.targetName)
        }
        return L("settings.backups.restore")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("settings.backups.title"))
                    .font(.headline)
                Text(L("settings.backups.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                Task { await vm.load() }
            } label: {
                Label(L("common.refresh"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(vm.isLoading)
        }
    }

    @ViewBuilder
    private var banners: some View {
        if let err = vm.errorMessage {
            banner(text: err, color: .red, icon: "exclamationmark.triangle.fill")
        }
        if let info = vm.infoMessage {
            banner(text: info, color: .green, icon: "checkmark.circle.fill")
        }
    }

    private func banner(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.callout)
            Spacer()
        }
        .padding(8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(L("settings.backups.empty"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(vm.entries) { entry in
                    row(for: entry)
                }
            }
        }
    }

    private func row(for entry: BackupEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName(for: entry.kind))
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(kindLabel(entry.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.dateFormatter.string(from: entry.createdAt))
                    .font(.caption)
                Text(Self.byteFormatter.string(fromByteCount: entry.sizeBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                revealInFinder(entry.backupURL)
            } label: {
                Image(systemName: "folder")
            }
            .help(L("settings.backups.reveal"))
            .buttonStyle(.borderless)

            Button {
                vm.requestRestore(entry)
            } label: {
                Text(L("settings.backups.restore"))
            }

            Button(role: .destructive) {
                vm.requestDelete(entry)
            } label: {
                Text(L("settings.backups.delete"))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func iconName(for kind: BackupEntry.Kind) -> String {
        switch kind {
        case .npmrc: return "leaf.circle.fill"
        case .mavenSettings: return "shippingbox.fill"
        }
    }

    private func kindLabel(_ kind: BackupEntry.Kind) -> String {
        switch kind {
        case .npmrc: return L("settings.backups.kind.npmrc")
        case .mavenSettings: return L("settings.backups.kind.mavenSettings")
        }
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
