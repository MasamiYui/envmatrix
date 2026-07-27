import Foundation

/// Supported container engines managed by EnvMatrix.
public enum ContainerEngine: String, CaseIterable, Sendable, Codable, Hashable {
    case docker
    case podman

    public var displayName: String {
        switch self {
        case .docker: return "Docker"
        case .podman: return "Podman"
        }
    }
}

/// TLS material used to secure a Docker daemon connection.
public struct DockerTLSOptions: Hashable, Sendable, Codable {
    public let caCert: String?
    public let clientCert: String?
    public let clientKey: String?
    public let skipVerify: Bool

    public init(
        caCert: String? = nil,
        clientCert: String? = nil,
        clientKey: String? = nil,
        skipVerify: Bool = false
    ) {
        self.caCert = caCert
        self.clientCert = clientCert
        self.clientKey = clientKey
        self.skipVerify = skipVerify
    }
}

/// A Docker CLI context describing how to reach a Docker daemon.
public struct DockerContext: Identifiable, Hashable, Sendable, Codable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let endpoint: String
    public let contextType: String
    public let isCurrent: Bool
    public let tlsEnabled: Bool?
    public let skipTLSVerify: Bool?

    public var isBuiltIn: Bool { name == "default" }

    public init(
        name: String,
        description: String,
        endpoint: String,
        contextType: String,
        isCurrent: Bool,
        tlsEnabled: Bool? = nil,
        skipTLSVerify: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.endpoint = endpoint
        self.contextType = contextType
        self.isCurrent = isCurrent
        self.tlsEnabled = tlsEnabled
        self.skipTLSVerify = skipTLSVerify
    }
}

/// A Podman system connection describing how to reach a Podman service.
public struct PodmanConnection: Identifiable, Hashable, Sendable, Codable {
    public var id: String { name }
    public let name: String
    public let uri: String
    public let identity: String
    public let isDefault: Bool
    public let isReadWrite: Bool

    public init(
        name: String,
        uri: String,
        identity: String,
        isDefault: Bool,
        isReadWrite: Bool = true
    ) {
        self.name = name
        self.uri = uri
        self.identity = identity
        self.isDefault = isDefault
        self.isReadWrite = isReadWrite
    }
}

/// Result of pinging a container engine context for reachability and version info.
public struct ContainerPingResult: Hashable, Sendable {
    public let engine: ContainerEngine
    public let contextName: String
    public let ok: Bool
    public let latencyMS: Int
    public let summary: String
    public let rawStderr: String

    public init(
        engine: ContainerEngine,
        contextName: String,
        ok: Bool,
        latencyMS: Int,
        summary: String,
        rawStderr: String = ""
    ) {
        self.engine = engine
        self.contextName = contextName
        self.ok = ok
        self.latencyMS = latencyMS
        self.summary = summary
        self.rawStderr = rawStderr
    }
}

/// Errors surfaced while discovering or interacting with container contexts.
public enum ContainerContextsError: Error, LocalizedError, Hashable, Sendable {
    case cliMissing(ContainerEngine)
    case commandFailed(ContainerEngine, String)
    case parseFailed(ContainerEngine, String)
    case timeout(ContainerEngine)
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .cliMissing(let engine):
            return "\(engine.displayName) CLI was not found on PATH."
        case .commandFailed(let engine, let detail):
            return "\(engine.displayName) command failed: \(detail)"
        case .parseFailed(let engine, let detail):
            return "Failed to parse \(engine.displayName) output: \(detail)"
        case .timeout(let engine):
            return "\(engine.displayName) command timed out."
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        }
    }
}
