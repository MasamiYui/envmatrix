import Foundation

@MainActor
public final class HostsViewModel: ObservableObject {
    @Published public var profiles: [HostsProfile] = []
    @Published public var selection: HostsProfile?
    @Published public var rawText: String = ""
    @Published public var document: HostsDocument = HostsDocument(lines: [], lineEnding: "\n", trailingNewline: true)
    @Published public var viewMode: HostsViewMode = .structured
    @Published public var systemHostsText: String = ""
    @Published public var isBusy: Bool = false
    @Published public var errorMessage: String?
    @Published public var lastBackupURL: URL?

    private let service: HostsService

    public init(service: HostsService = DefaultHostsService()) {
        self.service = service
    }

    public var systemMatchesCurrentProfile: Bool {
        !systemHostsText.isEmpty && systemHostsText == rawText
    }

    public func refresh() {
        self.isBusy = true
        self.errorMessage = nil
        let service = self.service
        Task.detached(priority: .utility) {
            let system = (try? service.readSystemHosts()) ?? ""
            var initialProfiles = service.listProfiles()
            if initialProfiles.isEmpty {
                if let created = try? service.writeProfile(name: "default", text: system) {
                    try? service.setDefaultProfile(created)
                    initialProfiles = service.listProfiles()
                }
            }
            let profiles = initialProfiles
            await MainActor.run {
                self.systemHostsText = system
                self.profiles = profiles
                let target: HostsProfile?
                if let current = self.selection,
                   let match = profiles.first(where: { $0.name == current.name }) {
                    target = match
                } else {
                    target = profiles.first(where: { $0.isDefault }) ?? profiles.first
                }
                if let target = target {
                    self.select(target)
                } else {
                    self.selection = nil
                    self.rawText = ""
                    self.document = HostsDocument(lines: [], lineEnding: "\n", trailingNewline: true)
                    self.isBusy = false
                }
            }
        }
    }

    public func select(_ profile: HostsProfile) {
        self.selection = profile
        self.isBusy = true
        self.errorMessage = nil
        let service = self.service
        Task.detached(priority: .utility) {
            let result: Result<String, Error>
            do {
                let text = try service.readProfile(profile)
                result = .success(text)
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                switch result {
                case .success(let text):
                    self.rawText = text
                    self.document = HostsParser.parse(text)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                self.isBusy = false
            }
        }
    }

    public func switchMode(to newMode: HostsViewMode) {
        if viewMode == newMode { return }
        switch (viewMode, newMode) {
        case (.structured, .raw):
            rawText = HostsParser.serialize(document)
        case (.raw, .structured):
            document = HostsParser.parse(rawText)
        default:
            break
        }
        viewMode = newMode
    }

    // MARK: - Entry CRUD

    public func addEntry() {
        let entry = HostsEntry(isEnabled: true, ip: "127.0.0.1", hostnames: ["example.local"], comment: nil)
        document.lines.append(.entry(entry))
    }

    public func removeEntry(id: UUID) {
        document.lines.removeAll { line in
            if case .entry(let e) = line, e.id == id { return true }
            return false
        }
    }

    public func toggleEntryEnabled(id: UUID) {
        for index in document.lines.indices {
            if case .entry(var existing) = document.lines[index], existing.id == id {
                existing.isEnabled.toggle()
                document.lines[index] = .entry(existing)
                return
            }
        }
    }

    public func updateEntry(
        id: UUID,
        ip: String? = nil,
        hostnames: [String]? = nil,
        comment: String?? = nil,
        isEnabled: Bool? = nil
    ) {
        for index in document.lines.indices {
            if case .entry(var existing) = document.lines[index], existing.id == id {
                if let ip = ip { existing.ip = ip }
                if let hostnames = hostnames { existing.hostnames = hostnames }
                if let comment = comment { existing.comment = comment }
                if let isEnabled = isEnabled { existing.isEnabled = isEnabled }
                document.lines[index] = .entry(existing)
                return
            }
        }
    }

    // MARK: - Profile Management

    public func saveProfile() {
        guard let selection = selection else { return }
        if viewMode == .structured {
            rawText = HostsParser.serialize(document)
        } else {
            document = HostsParser.parse(rawText)
        }
        self.isBusy = true
        self.errorMessage = nil
        let service = self.service
        let name = selection.name
        let text = rawText
        Task.detached(priority: .utility) {
            let result: Result<HostsProfile, Error>
            do {
                let p = try service.writeProfile(name: name, text: text)
                result = .success(p)
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                switch result {
                case .success:
                    self.profiles = service.listProfiles()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                self.isBusy = false
            }
        }
    }

    public func createProfile(name: String, text: String = "") {
        self.isBusy = true
        self.errorMessage = nil
        let service = self.service
        Task.detached(priority: .utility) {
            let result: Result<HostsProfile, Error>
            do {
                let p = try service.writeProfile(name: name, text: text)
                result = .success(p)
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                switch result {
                case .success(let profile):
                    self.profiles = service.listProfiles()
                    self.select(profile)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.isBusy = false
                }
            }
        }
    }

    public func duplicateAsProfile(name: String) {
        let text = viewMode == .structured ? HostsParser.serialize(document) : rawText
        createProfile(name: name, text: text)
    }

    public func renameSelectedProfile(to newName: String) {
        guard let selection = selection else { return }
        do {
            let updated = try service.renameProfile(selection, to: newName)
            self.profiles = service.listProfiles()
            self.selection = self.profiles.first(where: { $0.name == updated.name })
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func deleteSelectedProfile() {
        guard let selection = selection else { return }
        do {
            try service.deleteProfile(selection)
            self.profiles = service.listProfiles()
            self.selection = nil
            self.rawText = ""
            self.document = HostsDocument(lines: [], lineEnding: "\n", trailingNewline: true)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func setDefault() {
        guard let selection = selection else { return }
        do {
            try service.setDefaultProfile(selection)
            self.profiles = service.listProfiles()
            self.selection = self.profiles.first(where: { $0.name == selection.name })
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Apply

    public func applyToSystem() {
        if viewMode == .structured {
            rawText = HostsParser.serialize(document)
        }
        let text = rawText
        self.isBusy = true
        self.errorMessage = nil
        let service = self.service
        Task.detached(priority: .utility) {
            let result: Result<URL, Error>
            do {
                let backup = try service.writeSystemHosts(text: text)
                result = .success(backup)
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                switch result {
                case .success(let backup):
                    self.lastBackupURL = backup
                    self.systemHostsText = text
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                self.isBusy = false
            }
        }
    }
}
