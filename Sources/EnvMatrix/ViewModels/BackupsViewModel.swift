import Foundation
import SwiftUI

@MainActor
public final class BackupsViewModel: ObservableObject {
    @Published public var entries: [BackupEntry] = []
    @Published public var errorMessage: String?
    @Published public var infoMessage: String?
    @Published public var isLoading: Bool = false
    @Published public var pendingRestore: BackupEntry?
    @Published public var pendingDelete: BackupEntry?

    private let service: BackupService

    public init(service: BackupService = DefaultBackupService()) {
        self.service = service
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let all = await Task.detached(priority: .userInitiated) { [service] in
            service.listBackups()
        }.value
        self.entries = all
    }

    public func requestRestore(_ entry: BackupEntry) {
        pendingRestore = entry
    }

    public func cancelRestore() {
        pendingRestore = nil
    }

    public func confirmRestore() async {
        guard let entry = pendingRestore else { return }
        pendingRestore = nil
        errorMessage = nil
        infoMessage = nil
        do {
            try service.restore(entry)
            infoMessage = String(format: L("settings.backups.restoreSuccess"), entry.targetName)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func requestDelete(_ entry: BackupEntry) {
        pendingDelete = entry
    }

    public func cancelDelete() {
        pendingDelete = nil
    }

    public func confirmDelete() async {
        guard let entry = pendingDelete else { return }
        pendingDelete = nil
        errorMessage = nil
        infoMessage = nil
        do {
            try service.delete(entry)
            infoMessage = L("settings.backups.deleteSuccess")
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
