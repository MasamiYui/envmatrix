import Foundation

public protocol PodmanImageService {
    func list() async throws -> [ContainerImage]
    func pull(reference: String, onLine: @Sendable @escaping (String) -> Void) throws -> StreamingHandle
    func tag(source: String, destination: String) async throws
    func remove(id: String) async throws
    func prune(includeUnused: Bool) async throws -> ImagePruneResult
    func inspect(id: String) async throws -> String
}

public final class DefaultPodmanImageService: PodmanImageService {
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

    private func findPodmanBinary() async -> URL? {
        locatePodmanSync()
    }

    public func list() async throws -> [ContainerImage] {
        let podman = try await requirePodman()
        let result = try await runPodman(podman, ["images", "--format", "json"])
        try Self.checkNotRunning(result)
        if result.exitCode != 0 {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ContainerContextsError.commandFailed(.podman, msg)
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        guard let data = trimmed.data(using: .utf8) else {
            throw ContainerContextsError.parseFailed(.podman, String(trimmed.prefix(200)))
        }
        do {
            let raws = try JSONDecoder().decode([PodmanImageRaw].self, from: data)
            return raws.flatMap { $0.toContainerImages() }
        } catch {
            throw ContainerContextsError.parseFailed(.podman, String(trimmed.prefix(200)))
        }
    }

    public func pull(reference: String, onLine: @Sendable @escaping (String) -> Void) throws -> StreamingHandle {
        try validateRef(reference)
        guard let podman = locatePodmanSync() else {
            throw ContainerContextsError.cliMissing(.podman)
        }
        return executor.spawn(executable: podman, args: ["pull", reference], onLine: onLine)
    }

    public func tag(source: String, destination: String) async throws {
        try validateRef(source)
        try validateRef(destination)
        let podman = try await requirePodman()
        let result = try await runPodman(podman, ["tag", source, destination])
        try Self.checkNotRunning(result)
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.podman, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func remove(id: String) async throws {
        try validateID(id)
        let podman = try await requirePodman()
        let result = try await runPodman(podman, ["image", "rm", id])
        try Self.checkNotRunning(result)
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.podman, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func prune(includeUnused: Bool) async throws -> ImagePruneResult {
        let podman = try await requirePodman()
        let args: [String] = includeUnused
            ? ["image", "prune", "-a", "-f"]
            : ["image", "prune", "-f"]
        let result = try await runPodman(podman, args)
        try Self.checkNotRunning(result)
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.podman, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let reclaimed = Self.parseReclaimedBytes(from: result.stdout)
        return ImagePruneResult(reclaimedBytes: reclaimed, rawStdout: result.stdout, engine: .podman)
    }

    public func inspect(id: String) async throws -> String {
        try validateID(id)
        let podman = try await requirePodman()
        let result = try await runPodman(podman, ["image", "inspect", id])
        try Self.checkNotRunning(result)
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.podman, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout
    }

    private func requirePodman() async throws -> URL {
        guard let podman = await findPodmanBinary() else {
            throw ContainerContextsError.cliMissing(.podman)
        }
        return podman
    }

    private func locatePodmanSync() -> URL? {
        var searchDirs = shellPathResolver.resolvePathDirs()
        let fallbacks = ["/usr/local/bin", "/opt/homebrew/bin"]
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
            let candidate = dir.appendingPathComponent("podman")
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func runPodman(_ podman: URL, _ args: [String]) async throws -> ProcessResult {
        do {
            return try await executor.run(executable: podman, args: args, timeout: nil)
        } catch ProcessExecutorError.timeout {
            throw ContainerContextsError.timeout(.podman)
        } catch let err as ContainerContextsError {
            throw err
        } catch {
            throw ContainerContextsError.commandFailed(.podman, error.localizedDescription)
        }
    }

    static func checkNotRunning(_ result: ProcessResult) throws {
        guard result.exitCode != 0 else { return }
        let stderr = result.stderr
        let lower = stderr.lowercased()
        if lower.contains("cannot connect to podman") || lower.contains("unable to connect") {
            throw ContainerContextsError.notRunning(.podman, String(stderr.prefix(500)))
        }
    }

    static func parseReclaimedBytes(from stdout: String) -> Int64 {
        for line in stdout.split(whereSeparator: { $0.isNewline }) {
            let s = String(line)
            if let range = s.range(of: "Total reclaimed space:") {
                let tail = s[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if let bytes = HumanBytes.parse(tail) { return bytes }
            }
        }
        return 0
    }

    private func validateRef(_ ref: String) throws {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ContainerContextsError.invalidInput("Image reference must not be empty")
        }
        if trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            throw ContainerContextsError.invalidInput("Image reference must not contain whitespace")
        }
        if trimmed.rangeOfCharacter(from: .controlCharacters) != nil {
            throw ContainerContextsError.invalidInput("Image reference must not contain control characters")
        }
    }

    private func validateID(_ id: String) throws {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ContainerContextsError.invalidInput("Image id must not be empty")
        }
        if trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            throw ContainerContextsError.invalidInput("Image id must not contain whitespace")
        }
        if trimmed.rangeOfCharacter(from: .controlCharacters) != nil {
            throw ContainerContextsError.invalidInput("Image id must not contain control characters")
        }
    }
}

struct PodmanImageRaw: Decodable {
    let id: String
    let names: [String]?
    let digest: String?
    let size: Int64?
    let created: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case names = "Names"
        case digest = "Digest"
        case size = "Size"
        case created = "Created"
    }

    func toContainerImages() -> [ContainerImage] {
        let createdDate = Date(timeIntervalSince1970: TimeInterval(created ?? 0))
        let sizeBytes = size ?? 0
        let digestValue = digest
        let nameList = names ?? []
        if nameList.isEmpty {
            return [
                ContainerImage(
                    id: id,
                    repository: "<none>",
                    tag: "<none>",
                    digest: digestValue,
                    sizeBytes: sizeBytes,
                    createdAt: createdDate,
                    engine: .podman
                )
            ]
        }
        return nameList.map { full in
            let (repo, tag) = Self.splitRepoTag(full)
            return ContainerImage(
                id: id,
                repository: repo,
                tag: tag,
                digest: digestValue,
                sizeBytes: sizeBytes,
                createdAt: createdDate,
                engine: .podman
            )
        }
    }

    static func splitRepoTag(_ full: String) -> (String, String) {
        if let colonIdx = full.lastIndex(of: ":"), !full[full.index(after: colonIdx)...].contains("/") {
            let repo = String(full[..<colonIdx])
            let tag = String(full[full.index(after: colonIdx)...])
            return (repo, tag)
        }
        return (full, "latest")
    }
}

enum HumanBytes {
    static func parse(_ raw: String) -> Int64? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        let scanner = Scanner(string: trimmed)
        scanner.locale = Locale(identifier: "en_US_POSIX")
        guard let value = scanner.scanDouble() else { return nil }
        let unit = String(trimmed[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces).uppercased()
        let multiplier: Double
        switch unit {
        case "", "B": multiplier = 1
        case "KB": multiplier = 1_000
        case "MB": multiplier = 1_000_000
        case "GB": multiplier = 1_000_000_000
        case "TB": multiplier = 1_000_000_000_000
        case "KIB": multiplier = 1_024
        case "MIB": multiplier = 1_024 * 1_024
        case "GIB": multiplier = 1_024 * 1_024 * 1_024
        case "TIB": multiplier = 1_024 * 1_024 * 1_024 * 1_024
        default: multiplier = 1
        }
        return Int64(value * multiplier)
    }
}
