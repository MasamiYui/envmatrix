import Foundation

public enum CLIConfigServiceError: Error, LocalizedError {
    case fileNotFound(String)
    case invalidJSON(String)
    case configNotRegistered(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "Config file not found: \(path)"
        case .invalidJSON(let msg): return "Invalid JSON: \(msg)"
        case .configNotRegistered(let id): return "Config not registered: \(id)"
        }
    }
}

public protocol CLIConfigService {
    func list() -> [CLIConfig]
    func load(_ config: CLIConfig) throws -> [String: Any]
    func save(_ config: CLIConfig, values: [String: Any]) throws
}

public struct CLIConfigPath {
    public let id: String
    public let name: String
    public let url: URL

    public init(id: String, name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }
}

public final class DefaultCLIConfigService: CLIConfigService {
    private let configPaths: [CLIConfigPath]
    private let fileManager: FileManager

    public init(
        configPaths: [CLIConfigPath]? = nil,
        fileManager: FileManager = .default
    ) {
        if let configPaths = configPaths {
            self.configPaths = configPaths
        } else {
            let home = URL(fileURLWithPath: NSHomeDirectory())
            self.configPaths = [
                CLIConfigPath(
                    id: "claude-code",
                    name: "Claude Code",
                    url: home.appendingPathComponent(".claude/settings.json")
                ),
                CLIConfigPath(
                    id: "trae-cn",
                    name: "Trae CN",
                    url: home.appendingPathComponent(".trae-cn/config.json")
                ),
                CLIConfigPath(
                    id: "gemini",
                    name: "Gemini",
                    url: home.appendingPathComponent(".gemini/config.json")
                )
            ]
        }
        self.fileManager = fileManager
    }

    public func list() -> [CLIConfig] {
        var result: [CLIConfig] = []
        for entry in configPaths {
            guard fileManager.fileExists(atPath: entry.url.path) else { continue }
            let json = (try? readJSON(at: entry.url)) ?? [:]
            let model = json["model"] as? String
            let baseURL = (json["apiBaseURL"] as? String) ?? (json["baseURL"] as? String)
            let rawKey = (json["apiKey"] as? String) ?? (json["api_key"] as? String)
            let masked = rawKey.map { maskAPIKey($0) }
            result.append(CLIConfig(
                id: entry.id,
                displayName: entry.name,
                filePath: entry.url,
                model: model,
                apiBaseURL: baseURL,
                apiKeyMasked: masked
            ))
        }
        return result
    }

    public func load(_ config: CLIConfig) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: config.filePath.path) else {
            throw CLIConfigServiceError.fileNotFound(config.filePath.path)
        }
        return try readJSON(at: config.filePath)
    }

    public func save(_ config: CLIConfig, values: [String: Any]) throws {
        var existing: [String: Any] = [:]
        if fileManager.fileExists(atPath: config.filePath.path) {
            existing = (try? readJSON(at: config.filePath)) ?? [:]
        }
        let originalAPIKey = (existing["apiKey"] as? String) ?? (existing["api_key"] as? String)

        for (key, value) in values {
            if key == "apiKey" || key == "api_key" {
                if let str = value as? String, isMaskedAPIKey(str) {
                    // keep original; skip merging
                    continue
                }
            }
            existing[key] = value
        }

        // If caller supplied a masked apiKey and we skipped it above, ensure the original stays.
        if let originalAPIKey = originalAPIKey {
            let incomingKey = values["apiKey"] as? String ?? values["api_key"] as? String
            if let incomingKey = incomingKey, isMaskedAPIKey(incomingKey) {
                if existing["apiKey"] != nil {
                    existing["apiKey"] = originalAPIKey
                } else if existing["api_key"] != nil {
                    existing["api_key"] = originalAPIKey
                } else {
                    existing["apiKey"] = originalAPIKey
                }
            }
        }

        let parent = config.filePath.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let data = try JSONSerialization.data(
            withJSONObject: existing,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: config.filePath, options: .atomic)
    }

    // MARK: - Helpers

    private func readJSON(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIConfigServiceError.invalidJSON("root is not object at \(url.path)")
        }
        return obj
    }

    private func maskAPIKey(_ value: String) -> String {
        if value.count > 8 {
            let prefix = value.prefix(4)
            let suffix = value.suffix(4)
            return "\(prefix)****\(suffix)"
        }
        return "****"
    }

    private func isMaskedAPIKey(_ value: String) -> Bool {
        if value == "****" { return true }
        return value.contains("****")
    }
}
