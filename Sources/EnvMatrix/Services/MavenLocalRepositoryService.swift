import Foundation

public enum MavenLocalRepositoryError: Error, LocalizedError {
    case repositoryNotFound(String)
    case scanFailed(String)
    case deleteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .repositoryNotFound(let path):
            return "Maven local repository not found at: \(path)"
        case .scanFailed(let msg):
            return "Failed to scan local repository: \(msg)"
        case .deleteFailed(let msg):
            return "Failed to delete artifact: \(msg)"
        }
    }
}

public protocol MavenLocalRepositoryService {
    var repositoryURL: URL { get }
    var repositoryExists: Bool { get }
    func scan() throws -> [MavenArtifact]
    func totalSize() throws -> Int64
    func deleteArtifact(_ artifact: MavenArtifact) throws
    func deleteVersion(_ version: MavenArtifactVersion) throws
}

public final class DefaultMavenLocalRepositoryService: MavenLocalRepositoryService {
    public let repositoryURL: URL
    private let fileManager: FileManager

    public init(
        repositoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        if let repositoryURL = repositoryURL {
            self.repositoryURL = repositoryURL
        } else {
            self.repositoryURL = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".m2", isDirectory: true)
                .appendingPathComponent("repository", isDirectory: true)
        }
        self.fileManager = fileManager
    }

    public var repositoryExists: Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: repositoryURL.path, isDirectory: &isDir)
            && isDir.boolValue
    }

    public func scan() throws -> [MavenArtifact] {
        guard repositoryExists else {
            throw MavenLocalRepositoryError.repositoryNotFound(repositoryURL.path)
        }
        var artifacts: [MavenArtifact] = []
        try scanArtifactDirs(under: repositoryURL, into: &artifacts)
        return artifacts.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    public func totalSize() throws -> Int64 {
        guard repositoryExists else { return 0 }
        return directorySize(at: repositoryURL)
    }

    public func deleteArtifact(_ artifact: MavenArtifact) throws {
        let groupPath = artifact.groupId
            .split(separator: ".")
            .map(String.init)
            .reduce(repositoryURL) { $0.appendingPathComponent($1, isDirectory: true) }
        let artifactDir = groupPath.appendingPathComponent(artifact.artifactId, isDirectory: true)
        guard fileManager.fileExists(atPath: artifactDir.path) else {
            throw MavenLocalRepositoryError.deleteFailed("path not found: \(artifactDir.path)")
        }
        do {
            try fileManager.removeItem(at: artifactDir)
        } catch {
            throw MavenLocalRepositoryError.deleteFailed(error.localizedDescription)
        }
    }

    public func deleteVersion(_ version: MavenArtifactVersion) throws {
        guard fileManager.fileExists(atPath: version.path.path) else {
            throw MavenLocalRepositoryError.deleteFailed("path not found: \(version.path.path)")
        }
        do {
            try fileManager.removeItem(at: version.path)
        } catch {
            throw MavenLocalRepositoryError.deleteFailed(error.localizedDescription)
        }
    }

    // MARK: - Scanning

    /// Recursively walk the repository tree. An "artifact directory" is one whose
    /// direct children are version directories (each containing at least one file
    /// like a .jar/.pom). Everything above it forms the groupId (dot-separated).
    private func scanArtifactDirs(under root: URL, into results: inout [MavenArtifact]) throws {
        let rootPath = root.path
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        )
        guard let enumerator = enumerator else {
            throw MavenLocalRepositoryError.scanFailed("enumerator failed")
        }

        for case let dirURL as URL in enumerator {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dirURL.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            if isArtifactDirectory(dirURL) {
                if let artifact = buildArtifact(at: dirURL, rootPath: rootPath) {
                    results.append(artifact)
                }
                enumerator.skipDescendants()
            }
        }
    }

    /// A directory qualifies as an artifact directory when it contains at least one
    /// version subdirectory. A version subdirectory is one that holds files matching
    /// the expected Maven layout (e.g. `<artifactId>-<version>.pom` or `.jar`).
    private func isArtifactDirectory(_ dir: URL) -> Bool {
        guard let children = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        let artifactId = dir.lastPathComponent
        for child in children {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: child.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            // Look for a .pom or .jar named "<artifactId>-<version>.<ext>" inside.
            if let files = try? fileManager.contentsOfDirectory(atPath: child.path) {
                let prefix = "\(artifactId)-"
                for f in files where f.hasPrefix(prefix)
                    && (f.hasSuffix(".pom") || f.hasSuffix(".jar")
                        || f.hasSuffix(".aar") || f.hasSuffix(".module")) {
                    return true
                }
            }
        }
        return false
    }

    private func buildArtifact(at dir: URL, rootPath: String) -> MavenArtifact? {
        let artifactId = dir.lastPathComponent
        let parentPath = dir.deletingLastPathComponent().path
        guard parentPath.hasPrefix(rootPath) else { return nil }
        let relative = String(parentPath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let groupId = relative.replacingOccurrences(of: "/", with: ".")
        guard !groupId.isEmpty else { return nil }

        guard let versionDirs = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var versions: [MavenArtifactVersion] = []
        var total: Int64 = 0
        var latest: Date? = nil

        for v in versionDirs {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: v.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            let size = directorySize(at: v)
            let modified = (try? v.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            versions.append(
                MavenArtifactVersion(
                    version: v.lastPathComponent,
                    sizeBytes: size,
                    modifiedAt: modified,
                    path: v
                )
            )
            total += size
            if let m = modified {
                if let cur = latest {
                    if m > cur { latest = m }
                } else {
                    latest = m
                }
            }
        }
        guard !versions.isEmpty else { return nil }
        versions.sort { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
        return MavenArtifact(
            groupId: groupId,
            artifactId: artifactId,
            versions: versions,
            totalSizeBytes: total,
            latestModified: latest
        )
    }

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
}
