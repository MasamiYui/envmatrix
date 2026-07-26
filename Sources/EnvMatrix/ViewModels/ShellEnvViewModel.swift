import Foundation

public enum ShellEnvViewMode: String {
    case structured
    case raw
}

@MainActor
public final class ShellEnvViewModel: ObservableObject {
    @Published public var files: [ShellRcFile] = []
    @Published public var selection: ShellRcFile? = nil
    @Published public var rawText: String = ""
    @Published public var document: ShellEnvDocument = ShellEnvDocument(entries: [], lineEnding: "\n", trailingNewline: true)
    @Published public var viewMode: ShellEnvViewMode = .structured
    @Published public var errorMessage: String? = nil
    @Published public var isBusy: Bool = false
    @Published public var lastBackupURL: URL? = nil

    private let service: ShellEnvService

    public init(service: ShellEnvService = DefaultShellEnvService()) {
        self.service = service
    }

    public func refresh() {
        self.files = service.availableFiles()
        let target: ShellRcFile?
        if let current = selection {
            target = files.first(where: { $0.kind == current.kind }) ?? files.first(where: { $0.isCurrentShell }) ?? files.first
        } else {
            target = files.first(where: { $0.isCurrentShell }) ?? files.first
        }
        if let target = target {
            select(target)
        } else {
            self.selection = nil
            self.rawText = ""
            self.document = ShellEnvDocument(entries: [], lineEnding: "\n", trailingNewline: true)
        }
    }

    public func select(_ file: ShellRcFile) {
        self.selection = file
        self.isBusy = true
        self.errorMessage = nil
        let service = self.service
        Task.detached(priority: .utility) {
            let result: Result<String, Error>
            do {
                let text = try service.read(file)
                result = .success(text)
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                switch result {
                case .success(let text):
                    self.rawText = text
                    self.document = ShellEnvParser.parse(text)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                self.isBusy = false
            }
        }
    }

    public func save() {
        guard let file = selection else { return }
        if viewMode == .structured {
            rawText = ShellEnvParser.serialize(document)
        } else {
            document = ShellEnvParser.parse(rawText)
        }
        self.isBusy = true
        self.errorMessage = nil
        let service = self.service
        let textToWrite = rawText
        Task.detached(priority: .utility) {
            let result: Result<URL?, Error>
            do {
                let backup = try service.write(file, text: textToWrite)
                result = .success(backup)
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                switch result {
                case .success(let backup):
                    self.lastBackupURL = backup
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                self.isBusy = false
            }
        }
    }

    public func switchMode(to newMode: ShellEnvViewMode) {
        if viewMode == newMode { return }
        switch (viewMode, newMode) {
        case (.structured, .raw):
            rawText = ShellEnvParser.serialize(document)
        case (.raw, .structured):
            document = ShellEnvParser.parse(rawText)
        default:
            break
        }
        viewMode = newMode
    }

    public func addVariable() {
        let variable = ShellVariable(key: "NEW_KEY", value: "", quoting: .double, isExported: true)
        document.entries.append(.variable(variable))
    }

    public func removeVariable(id: UUID) {
        document.entries.removeAll { entry in
            if case .variable(let v) = entry, v.id == id { return true }
            return false
        }
    }

    public func updateVariable(id: UUID, key: String?, value: String?, quoting: ShellQuoting?, isExported: Bool?) {
        for index in document.entries.indices {
            if case .variable(let existing) = document.entries[index], existing.id == id {
                let updated = ShellVariable(
                    id: existing.id,
                    key: key ?? existing.key,
                    value: value ?? existing.value,
                    quoting: quoting ?? existing.quoting,
                    isExported: isExported ?? existing.isExported
                )
                document.entries[index] = .variable(updated)
                return
            }
        }
    }

    public func addPathAppendSegment(pathEntryID: UUID, segment: String) {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        for index in document.entries.indices {
            if case .pathAppend(let existing) = document.entries[index], existing.id == pathEntryID {
                var segments = existing.segments
                segments.append(trimmed)
                let updated = ShellPathAppend(id: existing.id, segments: segments, style: existing.style)
                document.entries[index] = .pathAppend(updated)
                return
            }
        }
    }

    public func removePathAppendSegment(pathEntryID: UUID, at index: Int) {
        for entryIndex in document.entries.indices {
            if case .pathAppend(let existing) = document.entries[entryIndex], existing.id == pathEntryID {
                var segments = existing.segments
                guard index >= 0, index < segments.count else { return }
                segments.remove(at: index)
                let updated = ShellPathAppend(id: existing.id, segments: segments, style: existing.style)
                document.entries[entryIndex] = .pathAppend(updated)
                return
            }
        }
    }

    public func addPathAppendEntry() {
        let entry = ShellPathAppend(segments: [], style: .doubleQuoted)
        document.entries.append(.pathAppend(entry))
    }

    public func removePathAppendEntry(id: UUID) {
        document.entries.removeAll { entry in
            if case .pathAppend(let p) = entry, p.id == id { return true }
            return false
        }
    }
}
