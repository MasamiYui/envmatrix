import Foundation
import SwiftUI

/// One thing EnvMatrix did on the user's behalf: a mirror switch, a cache
/// clean, a runtime activation, a hosts write… Entries that carry both a
/// target and a backup path can be rolled back from Settings › History.
public struct OperationEntry: Identifiable, Codable, Hashable {
    public enum Category: String, Codable, CaseIterable {
        case runtime, homebrew, registry, cache, hosts, shell, mcp, apps, other

        public var systemImage: String {
            switch self {
            case .runtime: return "cpu"
            case .homebrew: return "cube.box.fill"
            case .registry: return "globe"
            case .cache: return "internaldrive"
            case .hosts: return "network"
            case .shell: return "terminal.fill"
            case .mcp: return "bolt.horizontal.fill"
            case .apps: return "app.badge.checkmark"
            case .other: return "circle"
            }
        }
    }

    public let id: UUID
    public let date: Date
    public let category: Category
    public let title: String
    public let detail: String?
    /// File the operation rewrote, when it was a config write.
    public let targetPath: String?
    /// Backup taken before the write; enables rollback.
    public let backupPath: String?
    public var rolledBackAt: Date?
    public var succeeded: Bool

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        category: Category,
        title: String,
        detail: String? = nil,
        targetPath: String? = nil,
        backupPath: String? = nil,
        succeeded: Bool = true
    ) {
        self.id = id
        self.date = date
        self.category = category
        self.title = title
        self.detail = detail
        self.targetPath = targetPath
        self.backupPath = backupPath
        self.rolledBackAt = nil
        self.succeeded = succeeded
    }
}

public enum OperationLogError: Error, LocalizedError {
    case notRollbackable
    case backupMissing(String)

    public var errorDescription: String? {
        switch self {
        case .notRollbackable: return "This operation cannot be rolled back."
        case .backupMissing(let path): return "Backup file no longer exists: \(path)"
        }
    }
}

/// Persistent, app-wide timeline of operations with rollback for config
/// writes. Stored as JSON under ~/.envmatrix/operations.json.
@MainActor
public final class OperationLog: ObservableObject {
    public static let shared = OperationLog()

    @Published public private(set) var entries: [OperationEntry] = []

    public static let maxEntries = 500

    private let storeURL: URL
    private let fileManager: FileManager
    private let privilegedWriter: HostsPrivilegedWriter

    public init(
        storeURL: URL = FileSystem.envmatrixRoot.appendingPathComponent("operations.json"),
        fileManager: FileManager = .default,
        privilegedWriter: HostsPrivilegedWriter = OsascriptHostsPrivilegedWriter()
    ) {
        self.storeURL = storeURL
        self.fileManager = fileManager
        self.privilegedWriter = privilegedWriter
        load()
    }

    // MARK: - Recording

    @discardableResult
    public func record(
        _ category: OperationEntry.Category,
        title: String,
        detail: String? = nil,
        target: URL? = nil,
        backup: URL? = nil,
        succeeded: Bool = true
    ) -> OperationEntry {
        let entry = OperationEntry(
            category: category,
            title: title,
            detail: detail,
            targetPath: target?.path,
            backupPath: backup?.path,
            succeeded: succeeded
        )
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
        return entry
    }

    public func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Rollback

    public func canRollback(_ entry: OperationEntry) -> Bool {
        guard entry.succeeded, entry.rolledBackAt == nil,
              let backup = entry.backupPath, let target = entry.targetPath else { return false }
        return fileManager.fileExists(atPath: backup) && !target.isEmpty
    }

    /// Restores the backup over the target. The current target is backed
    /// up first so a rollback is itself reversible.
    public func rollback(_ entry: OperationEntry) throws {
        guard canRollback(entry), let backupPath = entry.backupPath, let targetPath = entry.targetPath else {
            throw OperationLogError.notRollbackable
        }
        let backupURL = URL(fileURLWithPath: backupPath)
        let targetURL = URL(fileURLWithPath: targetPath)
        guard fileManager.fileExists(atPath: backupPath) else {
            throw OperationLogError.backupMissing(backupPath)
        }

        var safetyCopy: URL?
        if targetPath == "/etc/hosts" {
            // Privileged path: stage a copy of the current file in the user's
            // backups dir, then let osascript copy the backup into place.
            let stamp = Self.stamp()
            let dir = FileSystem.envmatrixRoot.appendingPathComponent("hosts/backups", isDirectory: true)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let copy = dir.appendingPathComponent("hosts.\(stamp).rollback.bak")
            try? fileManager.copyItem(at: targetURL, to: copy)
            safetyCopy = copy
            try privilegedWriter.write(source: backupURL, to: targetPath)
        } else {
            if fileManager.fileExists(atPath: targetPath) {
                let copy = targetURL.deletingLastPathComponent()
                    .appendingPathComponent("\(targetURL.lastPathComponent).envmatrix.\(Self.stamp()).rollback.bak")
                try fileManager.copyItem(at: targetURL, to: copy)
                safetyCopy = copy
            }
            let data = try Data(contentsOf: backupURL)
            try data.write(to: targetURL, options: .atomic)
        }

        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].rolledBackAt = Date()
        }
        record(
            entry.category,
            title: String(format: L("history.rollback.entry"), entry.title),
            detail: targetPath,
            target: targetURL,
            backup: safetyCopy
        )
        NotificationCenter.default.post(name: .envMatrixSearchCorpusInvalidated, object: nil)
    }

    // MARK: - Helpers for callers

    /// Newest file in `directory` whose name starts with `prefix` and ends
    /// with `suffix`; used for services that write timestamped backups.
    public nonisolated static func latestBackup(in directory: URL, prefix: String, suffix: String,
                                                fileManager: FileManager = .default) -> URL? {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return nil }
        let candidates = names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }
        var best: (URL, Date)?
        for name in candidates {
            let url = directory.appendingPathComponent(name)
            let mtime = (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
            if best == nil || mtime > best!.1 { best = (url, mtime) }
        }
        return best?.0
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([OperationEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: storeURL, options: .atomic)
    }

    private nonisolated static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
