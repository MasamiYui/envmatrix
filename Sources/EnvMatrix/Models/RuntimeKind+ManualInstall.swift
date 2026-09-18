import Foundation

public extension RuntimeKind {
    /// A copy-pasteable terminal command that installs the given version
    /// through the ecosystem's own tooling. Used wherever EnvMatrix cannot
    /// (or should not) download a binary itself.
    func manualInstallCommand(version: String) -> String {
        switch self {
        case .node:
            return "brew install node@\(majorComponent(of: version))"
        case .python:
            return "brew install python@\(majorMinorComponent(of: version))"
        case .java:
            return "brew install --cask temurin@\(majorComponent(of: version))"
        case .go:
            return "brew install go@\(majorMinorComponent(of: version))"
        case .rust:
            return "rustup toolchain install \(version)"
        case .ruby:
            return "brew install ruby@\(majorMinorComponent(of: version))"
        case .php:
            return "brew install php@\(majorMinorComponent(of: version))"
        case .deno:
            return "brew install deno"
        case .bun:
            return "brew install oven-sh/bun/bun"
        case .dotnet:
            return "brew install --cask dotnet-sdk@\(majorComponent(of: version))"
        case .erlang:
            return "brew install erlang@\(majorComponent(of: version))"
        case .kotlin:
            return "brew install kotlin"
        }
    }

    /// Generic install command when no specific version is in play.
    var manualInstallCommand: String {
        switch self {
        case .node: return "brew install node"
        case .python: return "brew install python"
        case .java: return "brew install --cask temurin"
        case .go: return "brew install go"
        case .rust: return "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        case .ruby: return "brew install ruby"
        case .php: return "brew install php"
        case .deno: return "brew install deno"
        case .bun: return "brew install oven-sh/bun/bun"
        case .dotnet: return "brew install --cask dotnet-sdk"
        case .erlang: return "brew install erlang"
        case .kotlin: return "brew install kotlin"
        }
    }

    private func majorComponent(of version: String) -> String {
        let cleaned = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return cleaned.split(separator: ".").first.map(String.init) ?? cleaned
    }

    private func majorMinorComponent(of version: String) -> String {
        let cleaned = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parts = cleaned.split(separator: ".")
        guard parts.count >= 2 else { return cleaned }
        return "\(parts[0]).\(parts[1])"
    }
}
