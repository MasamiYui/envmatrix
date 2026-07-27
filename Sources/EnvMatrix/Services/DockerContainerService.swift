import Foundation

public protocol DockerContainerService {
    func list(all: Bool) async throws -> [ContainerInstance]
    func start(id: String) async throws
    func stop(id: String) async throws
    func restart(id: String) async throws
    func remove(id: String) async throws
    func logs(id: String, tail: Int) async throws -> String
    func inspect(id: String) async throws -> String
}

public final class DefaultDockerContainerService: DockerContainerService {
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

    public func list(all: Bool) async throws -> [ContainerInstance] {
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        var args: [String] = ["ps"]
        if all { args.append("-a") }
        args.append(contentsOf: ["--format", "{{json .}}"])
        let result = try await runDocker(docker, args)
        if result.exitCode != 0 {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ContainerContextsError.commandFailed(.docker, msg)
        }
        var instances: [ContainerInstance] = []
        for rawLine in result.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            guard let data = line.data(using: .utf8) else { continue }
            do {
                guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    let snippet = String(line.prefix(200))
                    throw ContainerContextsError.parseFailed(.docker, snippet)
                }
                instances.append(Self.parseInstance(obj))
            } catch let err as ContainerContextsError {
                throw err
            } catch {
                let snippet = String(line.prefix(200))
                throw ContainerContextsError.parseFailed(.docker, snippet)
            }
        }
        return instances
    }

    public func start(id: String) async throws {
        let trimmed = try validateID(id)
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let result = try await runDocker(docker, ["start", trimmed])
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.docker, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func stop(id: String) async throws {
        let trimmed = try validateID(id)
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let result = try await runDocker(docker, ["stop", trimmed])
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.docker, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func restart(id: String) async throws {
        let trimmed = try validateID(id)
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let result = try await runDocker(docker, ["restart", trimmed])
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.docker, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func remove(id: String) async throws {
        let trimmed = try validateID(id)
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let result = try await runDocker(docker, ["rm", trimmed])
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.docker, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func logs(id: String, tail: Int) async throws -> String {
        let trimmed = try validateID(id)
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let result = try await runDocker(docker, ["logs", "--tail", "\(tail)", trimmed])
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.docker, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout
    }

    public func inspect(id: String) async throws -> String {
        let trimmed = try validateID(id)
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let result = try await runDocker(docker, ["inspect", trimmed])
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.docker, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout
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

    private func validateID(_ id: String) throws -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ContainerContextsError.invalidInput("Container id must not be empty")
        }
        let shellMetacharacters: Set<Character> = [
            " ", "\t", "\n", "\r",
            ";", "&", "|", "`", "$",
            "<", ">", "(", ")", "{", "}",
            "\"", "'", "\\"
        ]
        for scalar in trimmed.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F {
                throw ContainerContextsError.invalidInput("Container id must not contain control characters")
            }
        }
        for ch in trimmed {
            if shellMetacharacters.contains(ch) {
                throw ContainerContextsError.invalidInput("Container id must not contain shell metacharacters")
            }
        }
        return trimmed
    }

    private static func parseInstance(_ obj: [String: Any]) -> ContainerInstance {
        let id = (obj["ID"] as? String) ?? ""
        let image = (obj["Image"] as? String) ?? ""
        let command = (obj["Command"] as? String) ?? ""
        let stateRaw = (obj["State"] as? String) ?? ""
        let status = (obj["Status"] as? String) ?? ""
        let namesRaw = (obj["Names"] as? String) ?? ""
        let names = namesRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let portsSummary = (obj["Ports"] as? String) ?? ""
        let createdAtRaw = (obj["CreatedAt"] as? String) ?? ""
        let createdAt = parseDate(createdAtRaw)
        return ContainerInstance(
            id: id,
            names: names,
            image: image,
            command: command,
            state: ContainerInstanceState.from(stateRaw),
            status: status,
            portsSummary: portsSummary,
            createdAt: createdAt,
            engine: .docker
        )
    }

    private static func parseDate(_ raw: String) -> Date {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return Date(timeIntervalSince1970: 0) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) { return d }
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        if let d = iso2.date(from: trimmed) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        if let d = df.date(from: trimmed) { return d }
        df.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        if let d = df.date(from: trimmed) { return d }
        return Date(timeIntervalSince1970: 0)
    }
}
