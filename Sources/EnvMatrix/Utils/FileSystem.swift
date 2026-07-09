import Foundation

public enum FileSystem {
    public static var homeURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
    }

    public static var envmatrixRoot: URL {
        homeURL.appendingPathComponent(".envmatrix", isDirectory: true)
    }

    public static var versionsDir: URL {
        envmatrixRoot.appendingPathComponent("versions", isDirectory: true)
    }

    public static var shimsDir: URL {
        envmatrixRoot.appendingPathComponent("shims", isDirectory: true)
    }

    public static func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [envmatrixRoot, versionsDir, shimsDir] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    public static func versionDir(kind: RuntimeKind, version: String) -> URL {
        versionsDir
            .appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }
}
