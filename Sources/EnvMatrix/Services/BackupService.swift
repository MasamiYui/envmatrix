import Foundation

public struct BackupEntry: Identifiable, Hashable {
    public enum Kind: String, Hashable {
        case npmrc
        case mavenSettings
    }

    public let id: String
    public let kind: Kind
    public let backupURL: URL
    public let targetURL: URL
    public let createdAt: Date
    public let sizeBytes: Int64

    public var displayName: String {
        backupURL.lastPathComponent
    }

    public var targetName: String {
        switch kind {
        case .npmrc: return "~/.npmrc"
        case .mavenSettings: return "~/.m2/settings.xml"
        }
    }
}

public protocol BackupService {
    func listBackups() -> [BackupEntry]
    func restore(_ entry: BackupEntry) throws
    func delete(_ entry: BackupEntry) throws
}

public enum BackupServiceError: Error, LocalizedError {
    case backupMissing
    case restoreFailed(String)
    case deleteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .backupMissing:
            return "Backup file no longer exists."
        case .restoreFailed(let msg):
            return "Failed to restore backup: \(msg)"
        case .deleteFailed(let msg):
            return "Failed to delete backup: \(msg)"
        }
    }
}

public final class DefaultBackupService: BackupService {
    private static let npmrcBackupName = ".npmrc.envmatrix.bak"
    private static let mavenBackupPattern = "settings.xml."
    private static let mavenBackupSuffix = ".bak"

    private let fileManager: FileManager
    private let homeURL: URL

    public init(fileManager: FileManager = .default, home: URL? = nil) {
        self.fileManager = fileManager
        self.homeURL = home ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    public func listBackups() -> [BackupEntry] {
        var entries: [BackupEntry] = []
        entries.append(contentsOf: listNpmrcBackups())
        entries.append(contentsOf: listMavenBackups())
        entries.sort { $0.createdAt > $1.createdAt }
        return entries
    }

    public func restore(_ entry: BackupEntry) throws {
        guard fileManager.fileExists(atPath: entry.backupURL.path) else {
            throw BackupServiceError.backupMissing
        }
        do {
            if fileManager.fileExists(atPath: entry.targetURL.path) {
                try fileManager.removeItem(at: entry.targetURL)
            }
            let parent = entry.targetURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parent.path) {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            try fileManager.copyItem(at: entry.backupURL, to: entry.targetURL)
        } catch {
            throw BackupServiceError.restoreFailed(error.localizedDescription)
        }
    }

    public func delete(_ entry: BackupEntry) throws {
        guard fileManager.fileExists(atPath: entry.backupURL.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: entry.backupURL)
        } catch {
            throw BackupServiceError.deleteFailed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func listNpmrcBackups() -> [BackupEntry] {
        let backupURL = homeURL.appendingPathComponent(Self.npmrcBackupName)
        guard fileManager.fileExists(atPath: backupURL.path) else { return [] }
        let targetURL = homeURL.appendingPathComponent(".npmrc")
        let attrs = try? fileManager.attributesOfItem(atPath: backupURL.path)
        let mtime = (attrs?[.modificationDate] as? Date) ?? Date()
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return [
            BackupEntry(
                id: backupURL.path,
                kind: .npmrc,
                backupURL: backupURL,
                targetURL: targetURL,
                createdAt: mtime,
                sizeBytes: size
            )
        ]
    }

    private func listMavenBackups() -> [BackupEntry] {
        let m2URL = homeURL.appendingPathComponent(".m2", isDirectory: true)
        guard fileManager.fileExists(atPath: m2URL.path) else { return [] }
        let targetURL = m2URL.appendingPathComponent("settings.xml")
        guard let files = try? fileManager.contentsOfDirectory(
            at: m2URL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        ) else { return [] }

        var results: [BackupEntry] = []
        for url in files {
            let name = url.lastPathComponent
            guard name.hasPrefix(Self.mavenBackupPattern),
                  name.hasSuffix(Self.mavenBackupSuffix),
                  name != "settings.xml"
            else { continue }
            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            let mtime = (attrs?[.modificationDate] as? Date) ?? Date()
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            results.append(
                BackupEntry(
                    id: url.path,
                    kind: .mavenSettings,
                    backupURL: url,
                    targetURL: targetURL,
                    createdAt: mtime,
                    sizeBytes: size
                )
            )
        }
        return results
    }
}
