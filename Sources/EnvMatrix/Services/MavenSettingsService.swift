import Foundation

public enum MavenSettingsError: Error, LocalizedError {
    case fileError(String)
    case parseError(String)
    case writeError(String)
    case notFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .fileError(let msg): return "Maven settings file error: \(msg)"
        case .parseError(let msg): return "Failed to parse settings.xml: \(msg)"
        case .writeError(let msg): return "Failed to write settings.xml: \(msg)"
        case .notFound(let id): return "Maven mirror not found: \(id.uuidString)"
        }
    }
}

public protocol MavenSettingsService {
    func read() throws -> MavenSettings
    func write(_ settings: MavenSettings) throws
    func addMirror(_ mirror: MavenMirror) throws
    func updateMirror(_ mirror: MavenMirror) throws
    func deleteMirror(_ id: UUID) throws
    func backup() throws -> URL?
    func presetMirrors() -> [MavenMirror]
    var settingsURL: URL { get }
}

public final class DefaultMavenSettingsService: MavenSettingsService {
    public let settingsURL: URL
    private let fileManager: FileManager

    public init(
        settingsURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        if let settingsURL = settingsURL {
            self.settingsURL = settingsURL
        } else {
            self.settingsURL = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".m2", isDirectory: true)
                .appendingPathComponent("settings.xml")
        }
        self.fileManager = fileManager
    }

    // MARK: - Public API

    public func read() throws -> MavenSettings {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return MavenSettings()
        }
        let data: Data
        do {
            data = try Data(contentsOf: settingsURL)
        } catch {
            throw MavenSettingsError.fileError(error.localizedDescription)
        }
        return try Self.parse(data: data)
    }

    public func write(_ settings: MavenSettings) throws {
        _ = try? backup()
        try ensureParentDir()
        let xml = Self.serialize(settings)
        do {
            try xml.write(to: settingsURL, atomically: true, encoding: .utf8)
        } catch {
            throw MavenSettingsError.writeError(error.localizedDescription)
        }
    }

    public func addMirror(_ mirror: MavenMirror) throws {
        var settings = try read()
        settings.mirrors.append(mirror)
        try write(settings)
    }

    public func updateMirror(_ mirror: MavenMirror) throws {
        var settings = try read()
        guard let idx = settings.mirrors.firstIndex(where: { $0.id == mirror.id }) else {
            throw MavenSettingsError.notFound(mirror.id)
        }
        settings.mirrors[idx] = mirror
        try write(settings)
    }

    public func deleteMirror(_ id: UUID) throws {
        var settings = try read()
        guard let idx = settings.mirrors.firstIndex(where: { $0.id == id }) else {
            throw MavenSettingsError.notFound(id)
        }
        settings.mirrors.remove(at: idx)
        try write(settings)
    }

    public func backup() throws -> URL? {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let backupURL = settingsURL
            .deletingLastPathComponent()
            .appendingPathComponent("settings.xml.\(stamp).bak")
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: settingsURL, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }

    public func presetMirrors() -> [MavenMirror] {
        [
            MavenMirror(
                mirrorId: "aliyun-public",
                name: "Aliyun Public",
                url: "https://maven.aliyun.com/repository/public",
                mirrorOf: "*",
                isEnabled: false
            ),
            MavenMirror(
                mirrorId: "tencent-cloud",
                name: "Tencent Cloud",
                url: "https://mirrors.cloud.tencent.com/nexus/repository/maven-public/",
                mirrorOf: "*",
                isEnabled: false
            ),
            MavenMirror(
                mirrorId: "huaweicloud",
                name: "HuaweiCloud",
                url: "https://repo.huaweicloud.com/repository/maven/",
                mirrorOf: "*",
                isEnabled: false
            ),
            MavenMirror(
                mirrorId: "netease",
                name: "Netease",
                url: "https://mirrors.163.com/maven/repository/maven-public/",
                mirrorOf: "*",
                isEnabled: false
            )
        ]
    }

    // MARK: - Helpers

    private func ensureParentDir() throws {
        let parent = settingsURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    // MARK: - XML Parsing

    internal static func parse(data: Data) throws -> MavenSettings {
        let parser = XMLParser(data: data)
        let delegate = MavenSettingsParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw MavenSettingsError.parseError(
                parser.parserError?.localizedDescription ?? "unknown"
            )
        }
        return MavenSettings(
            localRepository: delegate.localRepository,
            mirrors: delegate.mirrors
        )
    }

    // MARK: - XML Serialization

    internal static func serialize(_ settings: MavenSettings) -> String {
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<settings xmlns=\"http://maven.apache.org/SETTINGS/1.0.0\"")
        lines.append("          xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"")
        lines.append("          xsi:schemaLocation=\"http://maven.apache.org/SETTINGS/1.0.0 "
                     + "https://maven.apache.org/xsd/settings-1.0.0.xsd\">")
        if let local = settings.localRepository, !local.isEmpty {
            lines.append("  <localRepository>\(escape(local))</localRepository>")
        }
        let enabled = settings.mirrors.filter { $0.isEnabled }
        if !enabled.isEmpty {
            lines.append("  <mirrors>")
            for m in enabled {
                lines.append("    <mirror>")
                lines.append("      <id>\(escape(m.mirrorId))</id>")
                lines.append("      <name>\(escape(m.name))</name>")
                lines.append("      <url>\(escape(m.url))</url>")
                lines.append("      <mirrorOf>\(escape(m.mirrorOf))</mirrorOf>")
                lines.append("    </mirror>")
            }
            lines.append("  </mirrors>")
        }
        lines.append("</settings>")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - XMLParser Delegate

final class MavenSettingsParserDelegate: NSObject, XMLParserDelegate {
    var localRepository: String?
    var mirrors: [MavenMirror] = []

    private var path: [String] = []
    private var current: String = ""

    private var currentMirrorId: String = ""
    private var currentMirrorName: String = ""
    private var currentMirrorURL: String = ""
    private var currentMirrorOf: String = "central"

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        path.append(elementName)
        current = ""
        if elementName == "mirror" {
            currentMirrorId = ""
            currentMirrorName = ""
            currentMirrorURL = ""
            currentMirrorOf = "central"
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        current += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)

        if path == ["settings", "localRepository"] {
            localRepository = trimmed
        }

        if path.count >= 3, path[0] == "settings", path[1] == "mirrors", path[2] == "mirror" {
            if path.count == 4 {
                switch elementName {
                case "id": currentMirrorId = trimmed
                case "name": currentMirrorName = trimmed
                case "url": currentMirrorURL = trimmed
                case "mirrorOf": currentMirrorOf = trimmed
                default: break
                }
            }
            if elementName == "mirror" && path.count == 3 {
                mirrors.append(
                    MavenMirror(
                        mirrorId: currentMirrorId,
                        name: currentMirrorName.isEmpty ? currentMirrorId : currentMirrorName,
                        url: currentMirrorURL,
                        mirrorOf: currentMirrorOf.isEmpty ? "central" : currentMirrorOf,
                        isEnabled: true
                    )
                )
            }
        }

        if !path.isEmpty { path.removeLast() }
        current = ""
    }
}
