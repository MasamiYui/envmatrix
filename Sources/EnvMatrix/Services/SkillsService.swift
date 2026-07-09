import Foundation

public enum SkillsServiceError: Error, LocalizedError {
    case invalidPath(String)
    case renameFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let msg): return "Invalid skill path: \(msg)"
        case .renameFailed(let msg): return "Rename failed: \(msg)"
        }
    }
}

public protocol SkillsService {
    func list() throws -> [Skill]
    func enable(_ skill: Skill) throws -> Skill
    func disable(_ skill: Skill) throws -> Skill
    func delete(_ skill: Skill) throws
    func skillsDirectories() -> [URL]
}

public final class DefaultSkillsService: SkillsService {
    private let searchPaths: [URL]
    private let fileManager: FileManager

    public init(
        searchPaths: [URL]? = nil,
        fileManager: FileManager = .default
    ) {
        if let searchPaths = searchPaths {
            self.searchPaths = searchPaths
        } else {
            let home = URL(fileURLWithPath: NSHomeDirectory())
            self.searchPaths = [
                home.appendingPathComponent(".claude/skills", isDirectory: true),
                home.appendingPathComponent(".trae-cn/skills", isDirectory: true),
                home.appendingPathComponent(".trae/skills", isDirectory: true)
            ]
        }
        self.fileManager = fileManager
    }

    public func skillsDirectories() -> [URL] {
        searchPaths
    }

    public func list() throws -> [Skill] {
        var results: [Skill] = []
        for dir in searchPaths {
            guard fileManager.fileExists(atPath: dir.path) else { continue }
            let entries: [URL]
            do {
                entries = try fileManager.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                continue
            }
            for entry in entries {
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }
                let name = entry.lastPathComponent
                let isEnabled = !name.hasSuffix(".disabled")
                let displayName = isEnabled
                    ? name
                    : String(name.dropLast(".disabled".count))
                let source = deriveSource(from: dir)
                results.append(Skill(
                    name: displayName,
                    path: entry,
                    isEnabled: isEnabled,
                    source: source
                ))
            }
        }
        return results
    }

    public func enable(_ skill: Skill) throws -> Skill {
        let path = skill.path
        let name = path.lastPathComponent
        guard name.hasSuffix(".disabled") else {
            return skill
        }
        let newName = String(name.dropLast(".disabled".count))
        let newURL = path.deletingLastPathComponent().appendingPathComponent(newName, isDirectory: true)
        do {
            try fileManager.moveItem(at: path, to: newURL)
        } catch {
            throw SkillsServiceError.renameFailed(error.localizedDescription)
        }
        return Skill(
            name: newName,
            path: newURL,
            isEnabled: true,
            source: skill.source
        )
    }

    public func disable(_ skill: Skill) throws -> Skill {
        let path = skill.path
        let name = path.lastPathComponent
        guard !name.hasSuffix(".disabled") else {
            return skill
        }
        let newName = name + ".disabled"
        let newURL = path.deletingLastPathComponent().appendingPathComponent(newName, isDirectory: true)
        do {
            try fileManager.moveItem(at: path, to: newURL)
        } catch {
            throw SkillsServiceError.renameFailed(error.localizedDescription)
        }
        return Skill(
            name: name,
            path: newURL,
            isEnabled: false,
            source: skill.source
        )
    }

    public func delete(_ skill: Skill) throws {
        guard fileManager.fileExists(atPath: skill.path.path) else { return }
        try fileManager.removeItem(at: skill.path)
    }

    private func deriveSource(from dir: URL) -> String {
        let path = dir.path
        if path.contains(".claude") {
            return "claude"
        }
        if path.contains(".trae") {
            return "trae"
        }
        return "custom"
    }
}
