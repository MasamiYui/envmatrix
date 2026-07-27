import Foundation

/// Podman CLI system-connection management surface consumed by higher-level view models.
public protocol PodmanContextService {
    func isPodmanAvailable() async -> Bool
    func listConnections() async throws -> [PodmanConnection]
    func setDefault(_ name: String) async throws
    func addConnection(name: String, uri: String, identity: String?, makeDefault: Bool) async throws
    func replaceConnection(oldName: String, newName: String, uri: String, identity: String?, makeDefault: Bool) async throws
    func removeConnection(_ name: String) async throws
    func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult
}

/// Default implementation of `PodmanContextService` shelling out to the `podman` CLI.
public final class DefaultPodmanContextService: PodmanContextService {
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

    private func findPodmanBinary() async -> URL? {
        var searchDirs = shellPathResolver.resolvePathDirs()
        let fallbacks = [
            "/usr/local/bin",
            "/opt/homebrew/bin"
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
            let candidate = dir.appendingPathComponent("podman")
            if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    public func isPodmanAvailable() async -> Bool {
        await findPodmanBinary() != nil
    }

    public func listConnections() async throws -> [PodmanConnection] {
        guard let podman = await findPodmanBinary() else {
            throw ContainerContextsError.cliMissing(.podman)
        }
        let result: ProcessResult
        do {
            result = try await executor.run(
                executable: podman,
                args: ["system", "connection", "list", "--format", "json"],
                timeout: nil
            )
        } catch ProcessExecutorError.timeout {
            throw ContainerContextsError.timeout(.podman)
        } catch {
            throw ContainerContextsError.commandFailed(.podman, error.localizedDescription)
        }
        if result.exitCode != 0 {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ContainerContextsError.commandFailed(.podman, msg)
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        guard let data = trimmed.data(using: .utf8) else {
            let snippet = String(trimmed.prefix(200))
            throw ContainerContextsError.parseFailed(.podman, snippet)
        }
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            let snippet = String(trimmed.prefix(200))
            throw ContainerContextsError.parseFailed(.podman, snippet)
        }
        guard let array = root as? [[String: Any]] else {
            let snippet = String(trimmed.prefix(200))
            throw ContainerContextsError.parseFailed(.podman, snippet)
        }
        var connections: [PodmanConnection] = []
        for obj in array {
            let name = (obj["Name"] as? String) ?? ""
            let uri = (obj["URI"] as? String) ?? ""
            let identity = (obj["Identity"] as? String) ?? ""
            let isDefault = Self.parseBool(obj["Default"])
            let isReadWrite: Bool
            if let raw = obj["ReadWrite"] {
                isReadWrite = Self.parseBool(raw)
            } else {
                isReadWrite = true
            }
            connections.append(
                PodmanConnection(
                    name: name,
                    uri: uri,
                    identity: identity,
                    isDefault: isDefault,
                    isReadWrite: isReadWrite
                )
            )
        }
        return connections
    }

    public func setDefault(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ContainerContextsError.invalidInput("Connection name must not be empty")
        }
        guard let podman = await findPodmanBinary() else {
            throw ContainerContextsError.cliMissing(.podman)
        }
        let result = try await runPodman(podman, ["system", "connection", "default", trimmed])
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.podman, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func addConnection(name: String, uri: String, identity: String?, makeDefault: Bool) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURI = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ContainerContextsError.invalidInput("Connection name must not be empty")
        }
        guard !trimmedURI.isEmpty else {
            throw ContainerContextsError.invalidInput("Connection URI must not be empty")
        }
        guard let podman = await findPodmanBinary() else {
            throw ContainerContextsError.cliMissing(.podman)
        }
        var args: [String] = ["system", "connection", "add"]
        if makeDefault {
            args.append("--default")
        }
        if let identity = identity {
            let trimmedIdentity = identity.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedIdentity.isEmpty {
                args.append("--identity")
                args.append(trimmedIdentity)
            }
        }
        args.append(trimmedName)
        args.append(trimmedURI)
        let result = try await runPodman(podman, args)
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.podman, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func replaceConnection(oldName: String, newName: String, uri: String, identity: String?, makeDefault: Bool) async throws {
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty else {
            throw ContainerContextsError.invalidInput("Connection name must not be empty")
        }
        let existing = try await listConnections()
        guard let snapshot = existing.first(where: { $0.name == trimmedOld }) else {
            throw ContainerContextsError.invalidInput("Connection not found")
        }
        try await removeConnection(trimmedOld)
        do {
            try await addConnection(name: newName, uri: uri, identity: identity, makeDefault: makeDefault)
        } catch {
            let rollbackIdentity: String? = snapshot.identity.isEmpty ? nil : snapshot.identity
            try? await addConnection(
                name: snapshot.name,
                uri: snapshot.uri,
                identity: rollbackIdentity,
                makeDefault: snapshot.isDefault
            )
            throw error
        }
    }

    public func removeConnection(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ContainerContextsError.invalidInput("Connection name must not be empty")
        }
        guard let podman = await findPodmanBinary() else {
            throw ContainerContextsError.cliMissing(.podman)
        }
        let result = try await runPodman(podman, ["system", "connection", "remove", trimmed])
        if result.exitCode != 0 {
            throw ContainerContextsError.commandFailed(.podman, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func ping(_ name: String, timeout: TimeInterval) async throws -> ContainerPingResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ContainerContextsError.invalidInput("Connection name must not be empty")
        }
        guard let podman = await findPodmanBinary() else {
            throw ContainerContextsError.cliMissing(.podman)
        }
        let start = Date()
        let result: ProcessResult
        do {
            result = try await executor.run(
                executable: podman,
                args: ["--connection", trimmed, "system", "info", "--format", "json"],
                timeout: timeout
            )
        } catch ProcessExecutorError.timeout {
            throw ContainerContextsError.timeout(.podman)
        } catch {
            throw ContainerContextsError.commandFailed(.podman, error.localizedDescription)
        }
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        let summary = Self.parseInfoSummary(result.stdout)
        let stderrSnippet = String(result.stderr.prefix(500))
        return ContainerPingResult(
            engine: .podman,
            contextName: trimmed,
            ok: result.exitCode == 0,
            latencyMS: elapsed,
            summary: summary,
            rawStderr: stderrSnippet
        )
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

    private static func parseInfoSummary(_ stdout: String) -> String {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "podman"
        }
        var version = "n/a"
        if let versionObj = obj["version"] as? [String: Any] {
            if let v = versionObj["APIVersion"] as? String, !v.isEmpty {
                version = v
            } else if let v = versionObj["Version"] as? String, !v.isEmpty {
                version = v
            }
        }
        return "Client: \(version)"
    }

    private static func parseBool(_ raw: Any?) -> Bool {
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        if let s = raw as? String { return s.lowercased() == "true" }
        return false
    }
}
