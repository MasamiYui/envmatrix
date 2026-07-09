import Foundation
import SwiftUI

@MainActor
public final class DashboardViewModel: ObservableObject {
    public struct RuntimeSnapshot: Identifiable {
        public let kind: RuntimeKind
        public let activeVersion: String?
        public let isSystemDefault: Bool
        public var id: String { kind.rawValue }
    }

    @Published public var runtimes: [RuntimeSnapshot] = []
    @Published public var skillsCount: Int = 0
    @Published public var mcpCount: Int = 0
    @Published public var storageBytes: Int64 = 0
    @Published public var isLoading: Bool = false

    private let runtimeService: RuntimeService
    private let skillsService: SkillsService
    private let mcpService: MCPService
    private let versionsDir: URL
    private let shimsDir: URL
    private let fileManager: FileManager

    public init(
        runtimeService: RuntimeService = DefaultRuntimeService(),
        skillsService: SkillsService = DefaultSkillsService(),
        mcpService: MCPService = DefaultMCPService(),
        versionsDir: URL = FileSystem.versionsDir,
        shimsDir: URL = FileSystem.envmatrixRoot.appendingPathComponent("shims", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.runtimeService = runtimeService
        self.skillsService = skillsService
        self.mcpService = mcpService
        self.versionsDir = versionsDir
        self.shimsDir = shimsDir
        self.fileManager = fileManager
        self.runtimes = RuntimeKind.allCases.map {
            RuntimeSnapshot(kind: $0, activeVersion: nil, isSystemDefault: false)
        }
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let runtimeSvc = runtimeService
        let shims = shimsDir
        let fm = fileManager
        let snapshots = RuntimeKind.allCases.map { kind -> RuntimeSnapshot in
            let version = runtimeSvc.currentActive(kind: kind)
            let shimExists: Bool = {
                let shim = shims.appendingPathComponent(kind.binaryName)
                let attrs = try? fm.attributesOfItem(atPath: shim.path)
                return (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink
            }()
            return RuntimeSnapshot(
                kind: kind,
                activeVersion: version,
                isSystemDefault: version != nil && !shimExists
            )
        }
        self.runtimes = snapshots

        let skillsSvc = skillsService
        let mcpSvc = mcpService
        let dir = versionsDir

        let skillCount = (try? skillsSvc.list().count) ?? 0
        let mcpCountValue = (try? mcpSvc.list().count) ?? 0
        let bytes = await Self.folderSize(at: dir)

        self.skillsCount = skillCount
        self.mcpCount = mcpCountValue
        self.storageBytes = bytes
    }

    public static func folderSize(at url: URL) async -> Int64 {
        await Task.detached(priority: .utility) { () -> Int64 in
            FolderSizeCalculator.compute(at: url)
        }.value
    }
}

enum FolderSizeCalculator {
    static func compute(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true, let size = values?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
