import Foundation

public struct CLIConfig: Identifiable, Codable, Hashable {
    public let id: String
    public let displayName: String
    public let filePath: URL
    public var model: String?
    public var apiBaseURL: String?
    public var apiKeyMasked: String?

    public init(
        id: String,
        displayName: String,
        filePath: URL,
        model: String? = nil,
        apiBaseURL: String? = nil,
        apiKeyMasked: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.filePath = filePath
        self.model = model
        self.apiBaseURL = apiBaseURL
        self.apiKeyMasked = apiKeyMasked
    }
}
