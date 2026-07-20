import Foundation

public enum GoLocalCacheError: Error, LocalizedError {
    case cacheNotFound(String)
    case scanFailed(String)
    case deleteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cacheNotFound(let path):
            return "Go module cache not found at: \(path)"
        case .scanFailed(let msg):
            return "Failed to scan Go module cache: \(msg)"
        case .deleteFailed(let msg):
            return "Failed to delete Go module: \(msg)"
        }
    }
}

public protocol GoLocalCacheService {
    var cacheURL: URL { get }
    var cacheExists: Bool { get }
    func scan() throws -> [GoModuleArtifact]
    func totalSize() throws -> Int64
    func deleteModule(_ artifact: GoModuleArtifact) throws
    func deleteVersion(_ version: GoModuleVersion) throws
}

public final class DefaultGoLocalCacheService: GoLocalCacheService {
    public let cacheURL: URL
    private let fileManager: FileManager

    /// Top-level directory names inside the module cache that are NOT module dirs.
    private static let reservedTopLevelDirs: Set<String> = ["cache", "sumdb", "tmp"]

    public init(
        cacheURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        if let cacheURL = cacheURL {
            self.cacheURL = cacheURL
        } else {
            self.cacheURL = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("go/pkg/mod", isDirectory: true)
        }
        self.fileManager = fileManager
    }

    public var cacheExists: Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: cacheURL.path, isDirectory: &isDir)
            && isDir.boolValue
    }

    public func scan() throws -> [GoModuleArtifact] {
        guard cacheExists else {
            throw GoLocalCacheError.cacheNotFound(cacheURL.path)
        }
        var buckets: [String: [GoModuleVersion]] = [:]
        try scanModuleDirs(under: cacheURL, into: &buckets)

        var artifacts: [GoModuleArtifact] = []
        artifacts.reserveCapacity(buckets.count)
        for (modulePath, rawVersions) in buckets {
            let versions = rawVersions.sorted {
                $0.version.localizedStandardCompare($1.version) == .orderedDescending
            }
            let total = versions.reduce(Int64(0)) { $0 + $1.sizeBytes }
            let latest = versions.compactMap { $0.modifiedAt }.max()
            artifacts.append(
                GoModuleArtifact(
                    modulePath: modulePath,
                    versions: versions,
                    totalSizeBytes: total,
                    latestModified: latest
                )
            )
        }
        return artifacts.sorted {
            $0.modulePath.localizedCaseInsensitiveCompare($1.modulePath) == .orderedAscending
        }
    }

    public func totalSize() throws -> Int64 {
        guard cacheExists else { return 0 }
        return directorySize(at: cacheURL)
    }

    public func deleteModule(_ artifact: GoModuleArtifact) throws {
        for version in artifact.versions {
            try deleteVersion(version)
        }
    }

    public func deleteVersion(_ version: GoModuleVersion) throws {
        guard fileManager.fileExists(atPath: version.path.path) else {
            throw GoLocalCacheError.deleteFailed("path not found: \(version.path.path)")
        }
        do {
            try makeWritableRecursively(at: version.path)
            try fileManager.removeItem(at: version.path)
        } catch let error as GoLocalCacheError {
            throw error
        } catch {
            throw GoLocalCacheError.deleteFailed(error.localizedDescription)
        }
    }

    // MARK: - Scanning

    /// Walk the module cache tree. Each cached module version is a directory whose
    /// LEAF component is "<name>@<version>". The parent chain (excluding reserved
    /// top-level dirs) forms the escaped module path, which is unescaped here.
    private func scanModuleDirs(
        under root: URL,
        into buckets: inout [String: [GoModuleVersion]]
    ) throws {
        let rootPath = root.path
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            throw GoLocalCacheError.scanFailed("enumerator failed")
        }

        for case let dirURL as URL in enumerator {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dirURL.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            let relComponents = relativeComponents(of: dirURL, rootPath: rootPath)
            guard let first = relComponents.first else { continue }

            // Skip reserved top-level dirs entirely.
            if relComponents.count == 1, Self.reservedTopLevelDirs.contains(first) {
                enumerator.skipDescendants()
                continue
            }
            if Self.reservedTopLevelDirs.contains(first) {
                // Deeper inside a reserved subtree — should have been skipped above,
                // but guard against edge cases.
                enumerator.skipDescendants()
                continue
            }

            let leaf = relComponents[relComponents.count - 1]
            guard leaf.contains("@") else { continue }

            guard let atIdx = leaf.firstIndex(of: "@") else { continue }
            let name = String(leaf[..<atIdx])
            let version = String(leaf[leaf.index(after: atIdx)...])
            guard !name.isEmpty, !version.isEmpty else {
                enumerator.skipDescendants()
                continue
            }

            let parentComponents = Array(relComponents.dropLast())
            let escapedFull: String
            if parentComponents.isEmpty {
                escapedFull = name
            } else {
                escapedFull = parentComponents.joined(separator: "/") + "/" + name
            }
            let modulePath = unescapeModulePath(escapedFull)

            let size = directorySize(at: dirURL)
            let modified = (try? dirURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate

            let versionEntry = GoModuleVersion(
                version: version,
                sizeBytes: size,
                modifiedAt: modified,
                path: dirURL
            )
            buckets[modulePath, default: []].append(versionEntry)
            enumerator.skipDescendants()
        }
    }

    private func relativeComponents(of url: URL, rootPath: String) -> [String] {
        let path = url.path
        guard path.hasPrefix(rootPath) else { return [] }
        let relative = String(path.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return [] }
        return relative.split(separator: "/").map(String.init)
    }

    /// Unescape a Go module cache path segment. Go's escape rule writes any
    /// uppercase letter `U` as `!u` (a lowercase letter prefixed with `!`).
    /// So when unescaping: whenever we see `!`, uppercase the NEXT character
    /// and drop the `!`.
    func unescapeModulePath(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var it = s.makeIterator()
        while let c = it.next() {
            if c == "!" {
                if let next = it.next() {
                    out.append(Character(next.uppercased()))
                }
            } else {
                out.append(c)
            }
        }
        return out
    }

    // MARK: - File utilities

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
            )
            if let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Go's module cache marks files read-only. Before removal we walk the tree
    /// and OR the user-write bit (0o200) into each item's POSIX permissions,
    /// mirroring `chmod -R u+w`.
    private func makeWritableRecursively(at url: URL) throws {
        try setUserWritable(at: url)
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return }
        for case let itemURL as URL in enumerator {
            try setUserWritable(at: itemURL)
        }
    }

    private func setUserWritable(at url: URL) throws {
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        let current = (attrs?[.posixPermissions] as? NSNumber)?.intValue ?? 0o600
        let updated = current | 0o200
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: updated)],
            ofItemAtPath: url.path
        )
    }
}
