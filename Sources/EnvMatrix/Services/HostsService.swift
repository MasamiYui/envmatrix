import Foundation

public enum HostsServiceError: Error, LocalizedError {
    case readFailed(String)
    case writeFailed(String)
    case authCancelled
    case backupFailed(String)
    case invalidName(String)
    case profileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .readFailed(let msg): return "Failed to read hosts: \(msg)"
        case .writeFailed(let msg): return "Failed to write hosts: \(msg)"
        case .authCancelled: return "Authorization was cancelled"
        case .backupFailed(let msg): return "Failed to back up hosts: \(msg)"
        case .invalidName(let name): return "Invalid profile name: \(name)"
        case .profileNotFound(let name): return "Profile not found: \(name)"
        }
    }
}

public protocol HostsPrivilegedWriter {
    func write(source: URL, to systemPath: String) throws
}

public final class OsascriptHostsPrivilegedWriter: HostsPrivilegedWriter {
    public init() {}

    public func write(source: URL, to systemPath: String) throws {
        let command = "/bin/cp -f '\(source.path)' '\(systemPath)' && /bin/chmod 644 '\(systemPath)'"
        let script = "do shell script \"\(command)\" with administrator privileges"
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]

        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw HostsServiceError.writeFailed(error.localizedDescription)
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? ""
            if msg.contains("-128") || msg.localizedCaseInsensitiveContains("cancel") {
                throw HostsServiceError.authCancelled
            }
            throw HostsServiceError.writeFailed(msg.isEmpty ? "osascript exit \(process.terminationStatus)" : msg)
        }
    }
}

public protocol HostsService {
    var systemHostsPath: String { get }
    func profilesDirectory() -> URL
    func backupsDirectory() -> URL
    func readSystemHosts() throws -> String
    @discardableResult
    func writeSystemHosts(text: String) throws -> URL
    func listProfiles() -> [HostsProfile]
    func readProfile(_ profile: HostsProfile) throws -> String
    @discardableResult
    func writeProfile(name: String, text: String) throws -> HostsProfile
    func renameProfile(_ profile: HostsProfile, to newName: String) throws -> HostsProfile
    func deleteProfile(_ profile: HostsProfile) throws
    func setDefaultProfile(_ profile: HostsProfile) throws
    func defaultProfileName() -> String?
}

public final class DefaultHostsService: HostsService {
    public let systemHostsPath: String
    private let fileManager: FileManager
    private let baseDirectory: URL
    private let writer: HostsPrivilegedWriter

    public init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        systemHostsPath: String = "/etc/hosts",
        writer: HostsPrivilegedWriter = OsascriptHostsPrivilegedWriter()
    ) {
        self.fileManager = fileManager
        self.systemHostsPath = systemHostsPath
        self.writer = writer
        if let base = baseDirectory {
            self.baseDirectory = base
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.baseDirectory = appSupport
                .appendingPathComponent("EnvMatrix", isDirectory: true)
                .appendingPathComponent("hosts", isDirectory: true)
        }
        try? ensureDirectory(profilesDirectory())
        try? ensureDirectory(backupsDirectory())
    }

    public func profilesDirectory() -> URL {
        baseDirectory.appendingPathComponent("profiles", isDirectory: true)
    }

    public func backupsDirectory() -> URL {
        baseDirectory.appendingPathComponent("backups", isDirectory: true)
    }

    public func readSystemHosts() throws -> String {
        let url = URL(fileURLWithPath: systemHostsPath)
        guard fileManager.fileExists(atPath: url.path) else {
            throw HostsServiceError.readFailed("System hosts not found: \(url.path)")
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw HostsServiceError.readFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public func writeSystemHosts(text: String) throws -> URL {
        // 1. Backup existing hosts to user directory (no privilege required).
        try ensureDirectory(backupsDirectory())
        let timestamp = Self.timestampString(from: Date())
        let backupURL = backupsDirectory().appendingPathComponent("hosts.\(timestamp).bak")
        if fileManager.fileExists(atPath: systemHostsPath) {
            do {
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: backupURL)
                }
                try fileManager.copyItem(
                    at: URL(fileURLWithPath: systemHostsPath),
                    to: backupURL
                )
            } catch {
                throw HostsServiceError.backupFailed(error.localizedDescription)
            }
        }

        // 2. Materialize new content to temp file.
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let tmpURL = tmpDir.appendingPathComponent("envmatrix-hosts-\(timestamp)-\(UUID().uuidString).hosts")
        guard let data = text.data(using: .utf8) else {
            throw HostsServiceError.writeFailed("UTF-8 encoding failed")
        }
        do {
            try data.write(to: tmpURL, options: .atomic)
        } catch {
            throw HostsServiceError.writeFailed(error.localizedDescription)
        }

        // 3. Privileged copy via osascript.
        do {
            try writer.write(source: tmpURL, to: systemHostsPath)
        } catch {
            // keep tmp for troubleshooting
            throw error
        }

        // 4. Cleanup temp on success.
        try? fileManager.removeItem(at: tmpURL)
        return backupURL
    }

    public func listProfiles() -> [HostsProfile] {
        let dir = profilesDirectory()
        guard let items = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let defaultName = defaultProfileName()
        let profiles = items
            .filter { $0.pathExtension == "hosts" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { url -> HostsProfile in
                let name = url.deletingPathExtension().lastPathComponent
                return HostsProfile(name: name, url: url, isDefault: name == defaultName)
            }
        return profiles
    }

    public func readProfile(_ profile: HostsProfile) throws -> String {
        guard fileManager.fileExists(atPath: profile.url.path) else {
            throw HostsServiceError.profileNotFound(profile.name)
        }
        do {
            return try String(contentsOf: profile.url, encoding: .utf8)
        } catch {
            throw HostsServiceError.readFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public func writeProfile(name: String, text: String) throws -> HostsProfile {
        let safeName = try Self.validate(name: name)
        try ensureDirectory(profilesDirectory())
        let url = profilesDirectory().appendingPathComponent("\(safeName).hosts")
        guard let data = text.data(using: .utf8) else {
            throw HostsServiceError.writeFailed("UTF-8 encoding failed")
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw HostsServiceError.writeFailed(error.localizedDescription)
        }
        return HostsProfile(name: safeName, url: url, isDefault: defaultProfileName() == safeName)
    }

    public func renameProfile(_ profile: HostsProfile, to newName: String) throws -> HostsProfile {
        let safeName = try Self.validate(name: newName)
        if safeName == profile.name { return profile }
        let target = profilesDirectory().appendingPathComponent("\(safeName).hosts")
        if fileManager.fileExists(atPath: target.path) {
            throw HostsServiceError.invalidName("\(safeName) already exists")
        }
        do {
            try fileManager.moveItem(at: profile.url, to: target)
        } catch {
            throw HostsServiceError.writeFailed(error.localizedDescription)
        }
        if defaultProfileName() == profile.name {
            try? persistDefault(name: safeName)
        }
        return HostsProfile(id: profile.id, name: safeName, url: target, isDefault: defaultProfileName() == safeName)
    }

    public func deleteProfile(_ profile: HostsProfile) throws {
        if fileManager.fileExists(atPath: profile.url.path) {
            do {
                try fileManager.removeItem(at: profile.url)
            } catch {
                throw HostsServiceError.writeFailed(error.localizedDescription)
            }
        }
        if defaultProfileName() == profile.name {
            try? persistDefault(name: nil)
        }
    }

    public func setDefaultProfile(_ profile: HostsProfile) throws {
        try persistDefault(name: profile.name)
    }

    public func defaultProfileName() -> String? {
        let url = metaFileURL()
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let meta = try? JSONDecoder().decode(HostsMeta.self, from: data)
        else { return nil }
        return meta.defaultProfileName
    }

    // MARK: - Helpers

    private func ensureDirectory(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw HostsServiceError.writeFailed(error.localizedDescription)
            }
        }
    }

    private func metaFileURL() -> URL {
        profilesDirectory().appendingPathComponent(".meta.json")
    }

    private func persistDefault(name: String?) throws {
        try ensureDirectory(profilesDirectory())
        let meta = HostsMeta(defaultProfileName: name)
        let data = try JSONEncoder().encode(meta)
        try data.write(to: metaFileURL(), options: .atomic)
    }

    private static func validate(name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HostsServiceError.invalidName(name) }
        let invalid = CharacterSet(charactersIn: "/\\:")
        if trimmed.rangeOfCharacter(from: invalid) != nil {
            throw HostsServiceError.invalidName(name)
        }
        return trimmed
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

private struct HostsMeta: Codable {
    var defaultProfileName: String?
}
