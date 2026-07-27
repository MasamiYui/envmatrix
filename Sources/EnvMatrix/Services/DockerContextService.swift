import Foundation

/// Docker CLI context management surface consumed by higher-level view models.
public protocol DockerContextService {
    func isDockerAvailable() async -> Bool
    func listContexts() async throws -> [DockerContext]
    func useContext(_ name: String) async throws
    func createContext(name: String, host: String, description: String?, tls: DockerTLSOptions?) async throws
    func updateContext(name: String, host: String?, description: String?, tls: DockerTLSOptions?) async throws
    func removeContext(_ name: String) async throws
    func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult
}

/// Default implementation of `DockerContextService` shelling out to the `docker` CLI.
public final class DefaultDockerContextService: DockerContextService {
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

    public func isDockerAvailable() async -> Bool {
        await findDockerBinary() != nil
    }

    public func listContexts() async throws -> [DockerContext] {
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let result: ProcessResult
        do {
            result = try await executor.run(
                executable: docker,
                args: ["context", "ls", "--format", "{{json .}}"],
                timeout: nil
            )
        } catch ProcessExecutorError.timeout {
            throw ContainerContextsError.timeout(.docker)
        } catch {
            throw ContainerContextsError.commandFailed(.docker, error.localizedDescription)
        }
        if result.exitCode != 0 {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ContainerContextsError.commandFailed(.docker, msg)
        }
        var contexts: [DockerContext] = []
        for rawLine in result.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            guard let data = line.data(using: .utf8) else { continue }
            do {
                guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    let snippet = String(line.prefix(200))
                    throw ContainerContextsError.parseFailed(.docker, snippet)
                }
                let name = (obj["Name"] as? String) ?? ""
                let description = (obj["Description"] as? String) ?? ""
                let endpoint = (obj["DockerEndpoint"] as? String) ?? ""
                let contextType = (obj["ContextType"] as? String) ?? (obj["Type"] as? String) ?? ""
                let isCurrent = Self.parseBool(obj["Current"])
                contexts.append(
                    DockerContext(
                        name: name,
                        description: description,
                        endpoint: endpoint,
                        contextType: contextType,
                        isCurrent: isCurrent,
                        tlsEnabled: nil,
                        skipTLSVerify: nil
                    )
                )
            } catch let err as ContainerContextsError {
                throw err
            } catch {
                let snippet = String(line.prefix(200))
                throw ContainerContextsError.parseFailed(.docker, snippet)
            }
        }
        return contexts
    }

    public func useContext(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ContainerContextsError.invalidInput("Context name must not be empty")
        }
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let result = try await runDocker(docker, ["context", "use", trimmed])
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.docker, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func createContext(name: String, host: String, description: String?, tls: DockerTLSOptions?) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ContainerContextsError.invalidInput("Context name must not be empty")
        }
        guard !trimmedHost.isEmpty else {
            throw ContainerContextsError.invalidInput("Host must not be empty")
        }
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        var args: [String] = ["context", "create", trimmedName,
                              "--docker", Self.buildHostSpec(host: trimmedHost, tls: tls)]
        if let desc = description, !desc.isEmpty {
            args.append("--description")
            args.append(desc)
        }
        let result = try await runDocker(docker, args)
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.docker, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func updateContext(name: String, host: String?, description: String?, tls: DockerTLSOptions?) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ContainerContextsError.invalidInput("Context name must not be empty")
        }
        if host == nil && tls == nil && (description == nil || description?.isEmpty == true) {
            throw ContainerContextsError.invalidInput("Nothing to update")
        }
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        var args: [String] = ["context", "update", trimmedName]
        if host != nil || tls != nil {
            let hostValue = host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            args.append("--docker")
            args.append(Self.buildHostSpec(host: hostValue, tls: tls))
        }
        if let desc = description, !desc.isEmpty {
            args.append("--description")
            args.append(desc)
        }
        let result = try await runDocker(docker, args)
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.docker, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func removeContext(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ContainerContextsError.invalidInput("Context name must not be empty")
        }
        if trimmed == "default" {
            throw ContainerContextsError.invalidInput("Cannot remove built-in default context")
        }
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let result = try await runDocker(docker, ["context", "rm", trimmed])
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.docker, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ContainerContextsError.invalidInput("Context name must not be empty")
        }
        guard let docker = await findDockerBinary() else {
            throw ContainerContextsError.cliMissing(.docker)
        }
        let start = Date()
        let result: ProcessResult
        do {
            result = try await executor.run(
                executable: docker,
                args: ["--context", trimmed, "version", "--format", "{{json .}}"],
                timeout: timeout
            )
        } catch ProcessExecutorError.timeout {
            throw ContainerContextsError.timeout(.docker)
        } catch {
            throw ContainerContextsError.commandFailed(.docker, error.localizedDescription)
        }
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        let summary = Self.parseVersionSummary(result.stdout)
        let stderrSnippet = String(result.stderr.prefix(500))
        return ContainerPingResult(
            engine: .docker,
            contextName: trimmed,
            ok: result.exitCode == 0,
            latencyMS: elapsed,
            summary: summary,
            rawStderr: stderrSnippet
        )
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

    private static func buildHostSpec(host: String, tls: DockerTLSOptions?) -> String {
        var parts: [String] = []
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHost.isEmpty {
            parts.append("host=\(trimmedHost)")
        }
        if let tls = tls {
            if let ca = tls.caCert, !ca.isEmpty { parts.append("ca=\(ca)") }
            if let cert = tls.clientCert, !cert.isEmpty { parts.append("cert=\(cert)") }
            if let key = tls.clientKey, !key.isEmpty { parts.append("key=\(key)") }
            if tls.skipVerify { parts.append("skip-tls-verify=true") }
        }
        return parts.joined(separator: ",")
    }

    private static func parseVersionSummary(_ stdout: String) -> String {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var client = "n/a"
        var server = "n/a"
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let c = obj["Client"] as? [String: Any] {
                if let v = c["Version"] as? String, !v.isEmpty { client = v }
            }
            if let s = obj["Server"] as? [String: Any] {
                if let v = s["Version"] as? String, !v.isEmpty {
                    server = v
                } else if let components = s["Components"] as? [[String: Any]] {
                    for comp in components {
                        if let name = comp["Name"] as? String, name.localizedCaseInsensitiveContains("Engine"),
                           let details = comp["Details"] as? [String: Any],
                           let v = details["Version"] as? String, !v.isEmpty {
                            server = v
                            break
                        }
                    }
                }
            }
        }
        return "Client: \(client)  Server: \(server)"
    }

    private static func parseBool(_ raw: Any?) -> Bool {
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        if let s = raw as? String { return s.lowercased() == "true" }
        return false
    }
}
