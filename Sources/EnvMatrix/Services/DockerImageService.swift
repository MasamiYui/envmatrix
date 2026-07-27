import Foundation

public protocol DockerImageService {
    func list() async throws -> [ContainerImage]
    func pull(reference: String, onLine: @Sendable @escaping (String) -> Void) throws -> StreamingHandle
    func tag(source: String, destination: String) async throws
    func remove(id: String) async throws
    func prune(includeUnused: Bool) async throws -> ImagePruneResult
    func inspect(id: String) async throws -> String
}

public final class DefaultDockerImageService: DockerImageService {
    private let executor: StreamingProcessExecutor
    private let shellPathResolver: ShellPathResolver
    private let fileManager: FileManager

    public init(
        executor: StreamingProcessExecutor = DefaultProcessExecutor(),
        shellPathResolver: ShellPathResolver = DefaultShellPathResolver(),
        fileManager: FileManager = .default
    ) {
        self.executor = executor
        self.shellPathResolver = shellPathResolver
        self.fileManager = fileManager
    }

    private func findDockerBinary() async -> URL? {
        var searchDirs = shellPathResolver.resolvePathDirs()
        let fallbacks = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/Applications/Docker.app/Contents/Resources/bin"
        ]
        var seen = Set(searchDirs.map { $0.path })
        for fallback in fallbacks {
            if seen.insert(fallback).inserted {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: fallback, isDirectory: &isDir), isDir.boolValue {
                    searchDirs.append(URL(fileURLWithPath: fallback))
                }
            }
        }
        for dir in searchDirs {
            let candidate = dir.appendingPathComponent("docker")
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    public func list() async throws -> [ContainerImage] {
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let result = try await runDocker(docker, ["images", "--format", "{{json .}}"])
        if result.exitCode != 0 {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ContainerContextsError.commandFailed(.docker, msg)
        }
        var images: [ContainerImage] = []
        for rawLine in result.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            guard let data = line.data(using: .utf8) else { continue }
            let row: DockerImageRow
            do {
                row = try JSONDecoder().decode(DockerImageRow.self, from: data)
            } catch {
                let snippet = String(line.prefix(200))
                throw ContainerContextsError.parseFailed(.docker, snippet)
            }
            let repository = row.repository ?? ""
            let tag = row.tag ?? ""
            let id = row.id ?? ""
            let digest = (row.digest?.isEmpty == false && row.digest != "<none>") ? row.digest : nil
            let sizeBytes = Self.parseDockerSize(row.size ?? "")
            let createdAt = Self.parseDockerDate(row.createdAt)
            images.append(
                ContainerImage(
                    id: id,
                    repository: repository,
                    tag: tag,
                    digest: digest,
                    sizeBytes: sizeBytes,
                    createdAt: createdAt,
                    engine: .docker
                )
            )
        }
        return images
    }

    public func pull(reference: String, onLine: @Sendable @escaping (String) -> Void) throws -> StreamingHandle {
        try Self.validateRef(reference, field: "reference")
        guard let docker = shellPathResolverFindSync() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        return executor.spawn(executable: docker, args: ["pull", reference], onLine: onLine)
    }

    public func tag(source: String, destination: String) async throws {
        try Self.validateRef(source, field: "source")
        try Self.validateRef(destination, field: "destination")
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let result = try await runDocker(docker, ["tag", source, destination])
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.docker, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func remove(id: String) async throws {
        try Self.validateID(id)
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let result = try await runDocker(docker, ["rmi", id])
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.docker, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func prune(includeUnused: Bool) async throws -> ImagePruneResult {
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let args: [String] = includeUnused
            ? ["image", "prune", "-a", "-f"]
            : ["image", "prune", "-f"]
        let result = try await runDocker(docker, args)
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.docker, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let reclaimed = Self.parseReclaimedBytes(result.stdout)
        return ImagePruneResult(reclaimedBytes: reclaimed, rawStdout: result.stdout, engine: .docker)
    }

    public func inspect(id: String) async throws -> String {
        try Self.validateID(id)
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let result = try await runDocker(docker, ["inspect", id])
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.docker, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout
    }

    private func shellPathResolverFindSync() -> URL? {
        var searchDirs = shellPathResolver.resolvePathDirs()
        let fallbacks = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/Applications/Docker.app/Contents/Resources/bin"
        ]
        var seen = Set(searchDirs.map { $0.path })
        for fallback in fallbacks {
            if seen.insert(fallback).inserted {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: fallback, isDirectory: &isDir), isDir.boolValue {
                    searchDirs.append(URL(fileURLWithPath: fallback))
                }
            }
        }
        for dir in searchDirs {
            let candidate = dir.appendingPathComponent("docker")
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func runDocker(_ docker: URL, _ args: [String]) async throws -> ProcessResult {
        do {
            return try await executor.run(executable: docker, args: args, timeout: nil)
        } catch ProcessExecutorError.timeout {
            throw ContainerContextsError.timeout(.docker)
        } catch let err as ContainerContextsError {
            throw err
        } catch {
            throw ContainerContextsError.commandFailed(.docker, error.localizedDescription)
        }
    }

    private static let refPattern: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "^[A-Za-z0-9._:/@\\-]+$")
    }()

    private static func validateRef(_ value: String, field: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ContainerContextsError.invalidInput("\(field) must not be empty")
        }
        if trimmed.count > 256 {
            throw ContainerContextsError.invalidInput("\(field) exceeds 256 characters")
        }
        if containsForbiddenCharacters(trimmed) {
            throw ContainerContextsError.invalidInput("\(field) contains forbidden characters")
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        if refPattern.firstMatch(in: trimmed, options: [], range: range) == nil {
            throw ContainerContextsError.invalidInput("\(field) is not a valid reference")
        }
    }

    private static func validateID(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ContainerContextsError.invalidInput("id must not be empty")
        }
        if trimmed.count > 256 {
            throw ContainerContextsError.invalidInput("id exceeds 256 characters")
        }
        if containsForbiddenCharacters(trimmed) {
            throw ContainerContextsError.invalidInput("id contains forbidden characters")
        }
    }

    private static func containsForbiddenCharacters(_ value: String) -> Bool {
        for scalar in value.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F { return true }
        }
        let forbidden: Set<Character> = [" ", "`", "$", ";", "|", "&", ">", "<", "\n", "\r", "\t"]
        for ch in value where forbidden.contains(ch) { return true }
        return false
    }

    static func parseDockerSize(_ raw: String) -> Int64 {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        var numberEnd = trimmed.startIndex
        for idx in trimmed.indices {
            let ch = trimmed[idx]
            if ch.isNumber || ch == "." {
                numberEnd = trimmed.index(after: idx)
            } else {
                break
            }
        }
        let numberPart = String(trimmed[..<numberEnd]).trimmingCharacters(in: .whitespaces)
        let unitPart = String(trimmed[numberEnd...]).trimmingCharacters(in: .whitespaces).uppercased()
        guard let value = Double(numberPart) else { return 0 }
        let multiplier: Double
        switch unitPart {
        case "", "B":
            multiplier = 1
        case "KB":
            multiplier = 1_000
        case "MB":
            multiplier = 1_000_000
        case "GB":
            multiplier = 1_000_000_000
        case "TB":
            multiplier = 1_000_000_000_000
        case "KIB":
            multiplier = 1_024
        case "MIB":
            multiplier = 1_024 * 1_024
        case "GIB":
            multiplier = 1_024 * 1_024 * 1_024
        case "TIB":
            multiplier = 1_024 * 1_024 * 1_024 * 1_024
        default:
            multiplier = 1
        }
        return Int64((value * multiplier).rounded())
    }

    static func parseDockerDate(_ raw: String?) -> Date {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return Date()
        }
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd HH:mm:ss Z zzz"
                return f
            }(),
            {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
                return f
            }(),
            {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                return f
            }()
        ]
        for f in formatters {
            if let d = f.date(from: raw) { return d }
        }
        if let firstSpace = raw.range(of: " CST") {
            let stripped = String(raw[..<firstSpace.lowerBound])
            for f in formatters {
                if let d = f.date(from: stripped) { return d }
            }
        }
        return Date()
    }

    private static let reclaimedPattern: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "Total reclaimed space:\\s*([0-9.]+)\\s*([KMGT]?i?B)", options: [.caseInsensitive])
    }()

    static func parseReclaimedBytes(_ stdout: String) -> Int64 {
        let range = NSRange(stdout.startIndex..<stdout.endIndex, in: stdout)
        guard let match = reclaimedPattern.firstMatch(in: stdout, options: [], range: range),
              match.numberOfRanges >= 3,
              let numberRange = Range(match.range(at: 1), in: stdout),
              let unitRange = Range(match.range(at: 2), in: stdout) else {
            return 0
        }
        let combined = "\(stdout[numberRange])\(stdout[unitRange])"
        return parseDockerSize(combined)
    }
}

private struct DockerImageRow: Decodable {
    let repository: String?
    let tag: String?
    let id: String?
    let digest: String?
    let size: String?
    let createdAt: String?
    let createdSince: String?

    enum CodingKeys: String, CodingKey {
        case repository = "Repository"
        case tag = "Tag"
        case id = "ID"
        case digest = "Digest"
        case size = "Size"
        case createdAt = "CreatedAt"
        case createdSince = "CreatedSince"
    }
}
