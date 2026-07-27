import Foundation

public protocol PodmanContainerService {
    func list(all: Bool) async throws -> [ContainerInstance]
    func start(id: String) async throws
    func stop(id: String) async throws
    func restart(id: String) async throws
    func remove(id: String) async throws
    func logs(id: String, tail: Int) async throws -> String
    func inspect(id: String) async throws -> String
}

public final class DefaultPodmanContainerService: PodmanContainerService {
    private let executor: ProcessExecutor
    private let shellPathResolver: ShellPathResolver
    private let fileManager: FileManager

    public init(
        executor: ProcessExecutor = DefaultProcessExecutor(),
        shellPathResolver: ShellPathResolver = DefaultShellPathResolver(),
        fileManager: FileManager = .default
    ) {
        self.executor = executor
        self.shellPathResolver = shellPathResolver
        self.fileManager = fileManager
    }

    private func findPodmanBinary() -> URL? {
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

    public func list(all: Bool) async throws -> [ContainerInstance] {
        let podman = try requirePodman()
        var args: [String] = ["ps"]
        if all { args.append("-a") }
        args.append(contentsOf: ["--format", "json"])
        let result = try await runPodman(podman, args)
        try DefaultPodmanImageService.checkNotRunning(result)
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.podman, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        guard let data = trimmed.data(using: .utf8) else {
            throw ContainerContextsError.parseFailed(.podman, String(trimmed.prefix(200)))
        }
        do {
            let raws = try JSONDecoder().decode([PodmanContainerRaw].self, from: data)
            return raws.map { $0.toContainerInstance() }
        } catch {
            throw ContainerContextsError.parseFailed(.podman, String(trimmed.prefix(200)))
        }
    }

    public func start(id: String) async throws {
        try validateID(id)
        try await runSimple(["start", id])
    }

    public func stop(id: String) async throws {
        try validateID(id)
        try await runSimple(["stop", id])
    }

    public func restart(id: String) async throws {
        try validateID(id)
        try await runSimple(["restart", id])
    }

    public func remove(id: String) async throws {
        try validateID(id)
        try await runSimple(["rm", id])
    }

    public func logs(id: String, tail: Int) async throws -> String {
        try validateID(id)
        let tailValue = max(0, tail)
        let podman = try requirePodman()
        let result = try await runPodman(podman, ["logs", "--tail", "\(tailValue)", id])
        try DefaultPodmanImageService.checkNotRunning(result)
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.podman, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout
    }

    public func inspect(id: String) async throws -> String {
        try validateID(id)
        let podman = try requirePodman()
        let result = try await runPodman(podman, ["inspect", id])
        try DefaultPodmanImageService.checkNotRunning(result)
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.podman, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout
    }

    private func runSimple(_ args: [String]) async throws {
        let podman = try requirePodman()
        let result = try await runPodman(podman, args)
        try DefaultPodmanImageService.checkNotRunning(result)
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.podman, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func requirePodman() throws -> URL {
        guard let podman = findPodmanBinary() else {
            throw ContainerContextsError.cliMissing(.podman)
        }
        return podman
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

    private func validateID(_ id: String) throws {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ContainerContextsError.invalidInput("Container id must not be empty")
        }
        if trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            throw ContainerContextsError.invalidInput("Container id must not contain whitespace")
        }
        if trimmed.rangeOfCharacter(from: .controlCharacters) != nil {
            throw ContainerContextsError.invalidInput("Container id must not contain control characters")
        }
    }
}

struct PodmanContainerRaw: Decodable {
    let id: String
    let names: [String]?
    let image: String?
    let command: [String]?
    let state: String?
    let status: String?
    let ports: [PodmanPortRaw]?
    let created: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case names = "Names"
        case image = "Image"
        case command = "Command"
        case state = "State"
        case status = "Status"
        case ports = "Ports"
        case created = "Created"
    }

    func toContainerInstance() -> ContainerInstance {
        let stateValue = ContainerInstanceState.from(state ?? "")
        let commandJoined = (command ?? []).joined(separator: " ")
        let portsSummary = (ports ?? []).map { $0.summary }.joined(separator: ", ")
        let createdDate = Date(timeIntervalSince1970: TimeInterval(created ?? 0))
        return ContainerInstance(
            id: id,
            names: names ?? [],
            image: image ?? "",
            command: commandJoined,
            state: stateValue,
            status: status ?? "",
            portsSummary: portsSummary,
            createdAt: createdDate,
            engine: .podman
        )
    }
}

struct PodmanPortRaw: Decodable {
    let hostIP: String?
    let containerPort: Int?
    let hostPort: Int?
    let proto: String?

    enum CodingKeys: String, CodingKey {
        case hostIP = "host_ip"
        case containerPort = "container_port"
        case hostPort = "host_port"
        case proto = "protocol"
    }

    var summary: String {
        let host = hostIP ?? ""
        let hp = hostPort.map(String.init) ?? ""
        let cp = containerPort.map(String.init) ?? ""
        let pr = proto ?? ""
        if !host.isEmpty && !hp.isEmpty {
            return "\(host):\(hp)->\(cp)/\(pr)"
        }
        if !hp.isEmpty {
            return "\(hp)->\(cp)/\(pr)"
        }
        return "\(cp)/\(pr)"
    }
}
