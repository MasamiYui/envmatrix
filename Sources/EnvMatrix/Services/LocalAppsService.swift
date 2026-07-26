import AppKit
import Foundation

public protocol AppLauncher {
    func open(_ url: URL) throws
    func reveal(_ url: URL)
}

public final class DefaultAppLauncher: AppLauncher {
    public init() {}

    public func open(_ url: URL) throws {
        if !NSWorkspace.shared.open(url) {
            throw LocalAppsError.openFailed
        }
    }

    public func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

public protocol Trasher {
    func trash(_ url: URL) throws -> URL?
}

public final class DefaultTrasher: Trasher {
    public init() {}

    public func trash(_ url: URL) throws -> URL? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }
}

public enum LocalAppsError: LocalizedError {
    case openFailed
    case trashFailed(URL, Error)
    case protectedApp
    case notFound(URL)

    public var errorDescription: String? {
        switch self {
        case .openFailed:
            return "Failed to open application"
        case .trashFailed(let url, let error):
            return "Failed to move \(url.lastPathComponent) to Trash: \(error.localizedDescription)"
        case .protectedApp:
            return "This application is protected and cannot be moved to Trash"
        case .notFound(let url):
            return "File not found: \(url.path)"
        }
    }
}

public protocol LocalAppsService: AnyObject {
    func openApp(_ app: LocalApp) throws
    func revealInFinder(_ app: LocalApp)
    func moveToTrash(_ app: LocalApp) throws -> URL?
    func scanLeftovers(bundleId: String) async -> [LocalAppLeftover]
    func trashLeftovers(_ items: [LocalAppLeftover]) throws
    func isProtected(_ app: LocalApp) -> Bool
}

public final class DefaultLocalAppsService: LocalAppsService {
    private let launcher: AppLauncher
    private let trasher: Trasher
    private let fileManager: FileManager
    private let homeDirectory: URL

    public init(
        launcher: AppLauncher = DefaultAppLauncher(),
        trasher: Trasher = DefaultTrasher(),
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.launcher = launcher
        self.trasher = trasher
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    public func openApp(_ app: LocalApp) throws {
        try launcher.open(app.bundlePath)
    }

    public func revealInFinder(_ app: LocalApp) {
        launcher.reveal(app.bundlePath)
    }

    public func isProtected(_ app: LocalApp) -> Bool {
        if app.isProtected { return true }
        if app.bundleId.hasPrefix("com.apple.") { return true }
        if app.bundlePath.path.hasPrefix("/System/Applications/") { return true }
        return false
    }

    public func moveToTrash(_ app: LocalApp) throws -> URL? {
        if isProtected(app) {
            throw LocalAppsError.protectedApp
        }
        if !fileManager.fileExists(atPath: app.bundlePath.path) {
            throw LocalAppsError.notFound(app.bundlePath)
        }
        do {
            return try trasher.trash(app.bundlePath)
        } catch {
            throw LocalAppsError.trashFailed(app.bundlePath, error)
        }
    }

    public func scanLeftovers(bundleId: String) async -> [LocalAppLeftover] {
        let start = Date()
        let timeLimit: TimeInterval = 3.0
        let bid = bundleId.lowercased()
        guard !bid.isEmpty else { return [] }

        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        let targets: [(URL, LocalAppLeftoverKind)] = [
            (library.appendingPathComponent("Preferences", isDirectory: true), .preferences),
            (library.appendingPathComponent("Caches", isDirectory: true), .caches),
            (library.appendingPathComponent("Application Support", isDirectory: true), .appSupport),
            (library.appendingPathComponent("Logs", isDirectory: true), .logs),
            (library.appendingPathComponent("Saved Application State", isDirectory: true), .savedState),
            (library.appendingPathComponent("Containers", isDirectory: true), .containers),
            (library.appendingPathComponent("Group Containers", isDirectory: true), .groupContainers)
        ]

        var results: [LocalAppLeftover] = []
        for (dir, kind) in targets {
            if Date().timeIntervalSince(start) > timeLimit { return sorted(results) }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let items: [URL]
            do {
                items = try fileManager.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                continue
            }
            for item in items {
                if Date().timeIntervalSince(start) > timeLimit { return sorted(results) }
                let last = item.lastPathComponent.lowercased()
                let stem = item.deletingPathExtension().lastPathComponent.lowercased()
                if last.contains(bid) || stem.contains(bid) {
                    let size = Self.recursiveSize(of: item)
                    results.append(LocalAppLeftover(url: item, sizeBytes: size, kind: kind))
                }
            }
        }
        return sorted(results)
    }

    public func trashLeftovers(_ items: [LocalAppLeftover]) throws {
        var firstFailure: (URL, Error)?
        for item in items {
            do {
                _ = try trasher.trash(item.url)
            } catch {
                if firstFailure == nil {
                    firstFailure = (item.url, error)
                }
            }
        }
        if let failure = firstFailure {
            throw LocalAppsError.trashFailed(failure.0, failure.1)
        }
    }

    private func sorted(_ items: [LocalAppLeftover]) -> [LocalAppLeftover] {
        items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static func recursiveSize(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if !isDir.boolValue {
            let values = try? url.resourceValues(forKeys: Set(keys))
            return Int64(values?.totalFileAllocatedSize ?? 0)
        }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            guard let values, values.isRegularFile == true else { continue }
            if let size = values.totalFileAllocatedSize {
                total &+= Int64(size)
            }
        }
        return total
    }
}
