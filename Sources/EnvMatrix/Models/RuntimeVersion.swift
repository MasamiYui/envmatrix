import Foundation

public struct RuntimeVersion: Identifiable, Codable, Hashable {
    public let id: String
    public let kind: RuntimeKind
    public let version: String
    public let releaseDate: Date?
    public let downloadURL: URL?
    public let isLTS: Bool
    public let arch: String?
    public let installPath: URL?
    public let isSystem: Bool
    /// True when EnvMatrix can download and unpack a ready-to-run binary for
    /// this version. False for source-only distributions (Ruby, PHP) and for
    /// runtimes whose provider only lists versions (rustup, .NET, Erlang…),
    /// in which case the UI shows a manual install command instead.
    public let isInstallable: Bool

    public init(
        kind: RuntimeKind,
        version: String,
        releaseDate: Date? = nil,
        downloadURL: URL? = nil,
        isLTS: Bool = false,
        arch: String? = nil,
        installPath: URL? = nil,
        isSystem: Bool = false,
        isInstallable: Bool? = nil
    ) {
        if isSystem {
            self.id = "\(kind.rawValue)-system-\(version)"
        } else {
            self.id = "\(kind.rawValue)-\(version)"
        }
        self.kind = kind
        self.version = version
        self.releaseDate = releaseDate
        self.downloadURL = downloadURL
        self.isLTS = isLTS
        self.arch = arch
        self.installPath = installPath
        self.isSystem = isSystem
        self.isInstallable = isInstallable ?? (downloadURL != nil)
    }
}
