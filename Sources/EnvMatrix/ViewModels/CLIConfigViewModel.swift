import Foundation

@MainActor
public final class CLIConfigViewModel: ObservableObject {
    @Published public var configs: [CLIConfig] = []
    @Published public var selection: CLIConfig? = nil
    @Published public var model: String = ""
    @Published public var apiBaseURL: String = ""
    @Published public var apiKey: String = ""
    @Published public var errorMessage: String? = nil

    private let service: CLIConfigService

    public init(service: CLIConfigService = DefaultCLIConfigService()) {
        self.service = service
    }

    public func refresh() {
        self.configs = service.list()
        if let current = selection,
           let refreshed = configs.first(where: { $0.id == current.id }) {
            self.selection = refreshed
        }
    }

    public func select(_ config: CLIConfig) {
        self.selection = config
        do {
            let values = try service.load(config)
            self.model = (values["model"] as? String) ?? ""
            let baseURL = (values["apiBaseURL"] as? String)
                ?? (values["baseURL"] as? String)
                ?? ""
            self.apiBaseURL = baseURL
            self.apiKey = config.apiKeyMasked ?? ""
        } catch {
            self.errorMessage = error.localizedDescription
            self.model = config.model ?? ""
            self.apiBaseURL = config.apiBaseURL ?? ""
            self.apiKey = config.apiKeyMasked ?? ""
        }
    }

    public func save() {
        guard let selection = selection else { return }
        var values: [String: Any] = [
            "model": model,
            "apiBaseURL": apiBaseURL
        ]
        if !isMaskedAPIKey(apiKey) && !apiKey.isEmpty {
            values["apiKey"] = apiKey
        }
        do {
            try service.save(selection, values: values)
            refresh()
            if let updated = configs.first(where: { $0.id == selection.id }) {
                self.selection = updated
                self.apiKey = updated.apiKeyMasked ?? ""
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func isMaskedAPIKey(_ value: String) -> Bool {
        if value == "****" { return true }
        return value.contains("****")
    }
}
