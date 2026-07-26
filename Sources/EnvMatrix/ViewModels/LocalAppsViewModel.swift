import Foundation

public enum LocalAppSourceFilter: String, CaseIterable, Codable {
    case all
    case appStore
    case brewCask
    case other
}

public enum LocalAppSortKey: String, CaseIterable, Codable {
    case name
    case size
    case source
}

@MainActor
public final class LocalAppsViewModel: ObservableObject {
    @Published public var apps: [LocalApp] = []
    @Published public var searchText: String = ""
    @Published public var sourceFilter: LocalAppSourceFilter = .all
    @Published public var sortKey: LocalAppSortKey = .name
    @Published public var isBusy: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var pendingUninstall: LocalApp? = nil
    @Published public var pendingLeftovers: [LocalAppLeftover] = []
    @Published public var lastUninstalledBundleId: String? = nil

    private let scanner: LocalAppsScanner
    private let service: LocalAppsService
    private let roots: [URL]

    public init(scanner: LocalAppsScanner, service: LocalAppsService, roots: [URL]? = nil) {
        self.scanner = scanner
        self.service = service
        let defaults: [URL] = roots ?? [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        let fm = FileManager.default
        self.roots = defaults.filter { url in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    public var filteredApps: [LocalApp] {
        var result = apps

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { app in
                app.name.range(of: query, options: .caseInsensitive) != nil
                    || app.displayName.range(of: query, options: .caseInsensitive) != nil
                    || app.bundleId.range(of: query, options: .caseInsensitive) != nil
            }
        }

        switch sourceFilter {
        case .all:
            break
        case .appStore:
            result = result.filter { app in
                if case .appStore = app.source { return true }
                return false
            }
        case .brewCask:
            result = result.filter { app in
                if case .brewCask = app.source { return true }
                return false
            }
        case .other:
            result = result.filter { app in
                if case .other = app.source { return true }
                return false
            }
        }

        switch sortKey {
        case .name:
            result.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .size:
            result.sort { $0.sizeBytes > $1.sizeBytes }
        case .source:
            result.sort { lhs, rhs in
                let lo = Self.sourceOrder(lhs.source)
                let ro = Self.sourceOrder(rhs.source)
                if lo != ro { return lo < ro }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }

        return result
    }

    public func refresh() {
        self.isBusy = true
        self.errorMessage = nil
        let scanner = self.scanner
        let roots = self.roots
        Task.detached(priority: .utility) {
            let outcome: Result<[LocalApp], Error>
            do {
                let scanned = try await scanner.scan(roots: roots)
                outcome = .success(scanned)
            } catch {
                outcome = .failure(error)
            }
            await MainActor.run {
                switch outcome {
                case .success(let list):
                    self.apps = list
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                self.isBusy = false
            }
        }
    }

    public func open(_ app: LocalApp) {
        do {
            try service.openApp(app)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func reveal(_ app: LocalApp) {
        service.revealInFinder(app)
    }

    public func requestUninstall(_ app: LocalApp) {
        if service.isProtected(app) {
            self.errorMessage = LocalAppsError.protectedApp.errorDescription
            return
        }
        self.pendingUninstall = app
    }

    public func cancelUninstall() {
        self.pendingUninstall = nil
    }

    public func confirmUninstall() {
        guard let app = pendingUninstall else { return }
        self.pendingUninstall = nil
        self.isBusy = true
        self.errorMessage = nil
        let service = self.service
        Task.detached(priority: .utility) {
            let outcome: Result<(String, [LocalAppLeftover]), Error>
            do {
                _ = try service.moveToTrash(app)
                let bundleId = app.bundleId
                let leftovers = await service.scanLeftovers(bundleId: bundleId)
                outcome = .success((bundleId, leftovers))
            } catch {
                outcome = .failure(error)
            }
            await MainActor.run {
                switch outcome {
                case .success(let (bundleId, leftovers)):
                    self.apps.removeAll { $0.bundlePath == app.bundlePath }
                    self.pendingLeftovers = leftovers
                    self.lastUninstalledBundleId = bundleId
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                self.isBusy = false
            }
        }
    }

    public func dismissLeftovers() {
        self.pendingLeftovers = []
        self.lastUninstalledBundleId = nil
    }

    public func confirmLeftoverTrash(selection: Set<LocalAppLeftover.ID>) {
        let items = pendingLeftovers.filter { selection.contains($0.id) }
        if items.isEmpty { return }
        self.isBusy = true
        self.errorMessage = nil
        let service = self.service
        Task.detached(priority: .utility) {
            let outcome: Result<Void, Error>
            do {
                try service.trashLeftovers(items)
                outcome = .success(())
            } catch {
                outcome = .failure(error)
            }
            await MainActor.run {
                switch outcome {
                case .success:
                    self.pendingLeftovers = []
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                self.isBusy = false
            }
        }
    }

    public func isProtected(_ app: LocalApp) -> Bool {
        service.isProtected(app)
    }

    private static func sourceOrder(_ source: LocalAppSource) -> Int {
        switch source {
        case .appStore: return 0
        case .brewCask: return 1
        case .other: return 2
        }
    }
}
