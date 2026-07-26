import Foundation
import AppKit

public struct GradleArtifact: Identifiable, Sendable, Hashable {
    public let id: String
    public let group: String
    public let artifact: String
    public let version: String
    public let url: URL
    public let sizeBytes: Int64
    public let modifiedAt: Date?
}

public struct GradleWrapperDist: Identifiable, Sendable, Hashable {
    public let id: String
    public let versionLabel: String
    public let url: URL
    public let sizeBytes: Int64
    public let modifiedAt: Date?
}

public enum GradleCacheService {
    public static func gradleHome(fm: FileManager = .default) -> URL {
        FileSystem.homeURL.appendingPathComponent(".gradle", isDirectory: true)
    }

    public static func scanArtifacts(fm: FileManager = .default, home: URL? = nil) -> [GradleArtifact] {
        let base = (home ?? gradleHome(fm: fm))
            .appendingPathComponent("caches", isDirectory: true)
            .appendingPathComponent("modules-2", isDirectory: true)
            .appendingPathComponent("files-2.1", isDirectory: true)
        guard Self.directoryExists(base, fm: fm) else { return [] }
        var result: [GradleArtifact] = []
        guard let groupURLs = try? fm.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        for groupURL in groupURLs where Self.isDirectory(groupURL, fm: fm) {
            let group = groupURL.lastPathComponent
            guard let artifactURLs = try? fm.contentsOfDirectory(
                at: groupURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for artifactURL in artifactURLs where Self.isDirectory(artifactURL, fm: fm) {
                let artifact = artifactURL.lastPathComponent
                guard let versionURLs = try? fm.contentsOfDirectory(
                    at: artifactURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for versionURL in versionURLs where Self.isDirectory(versionURL, fm: fm) {
                    let version = versionURL.lastPathComponent
                    let size = Self.directorySize(at: versionURL, fm: fm)
                    let mtime = (try? versionURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate
                    let id = "\(group):\(artifact):\(version)"
                    result.append(
                        GradleArtifact(
                            id: id,
                            group: group,
                            artifact: artifact,
                            version: version,
                            url: versionURL,
                            sizeBytes: size,
                            modifiedAt: mtime
                        )
                    )
                }
            }
        }
        return result
    }

    public static func scanWrapperDists(fm: FileManager = .default, home: URL? = nil) -> [GradleWrapperDist] {
        let base = (home ?? gradleHome(fm: fm))
            .appendingPathComponent("wrapper", isDirectory: true)
            .appendingPathComponent("dists", isDirectory: true)
        guard Self.directoryExists(base, fm: fm) else { return [] }
        guard let entries = try? fm.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [GradleWrapperDist] = []
        for entry in entries where Self.isDirectory(entry, fm: fm) {
            let name = entry.lastPathComponent
            guard name.hasPrefix("gradle-") else { continue }
            let size = Self.directorySize(at: entry, fm: fm)
            let mtime = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            result.append(
                GradleWrapperDist(
                    id: name,
                    versionLabel: name,
                    url: entry,
                    sizeBytes: size,
                    modifiedAt: mtime
                )
            )
        }
        return result
    }

    public static func moveToTrash(_ url: URL) throws {
        var resulting: NSURL? = nil
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
    }

    // MARK: - Private helpers

    private static func directoryExists(_ url: URL, fm: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func isDirectory(_ url: URL, fm: FileManager) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private static func directorySize(at url: URL, fm: FileManager) -> Int64 {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if vals?.isRegularFile == true, let s = vals?.fileSize {
                total += Int64(s)
            }
        }
        return total
    }
}
