import Foundation

public struct RustProvider: VersionProvider {
    public let kind: RuntimeKind = .rust

    public init() {}

    public func listAvailable() async throws -> [RuntimeVersion] {
        do {
            let result = try await Shell.run("/usr/bin/env", ["rustup", "toolchain", "list"])
            guard result.exitCode == 0 else {
                return []
            }
            return Self.parse(output: result.stdout)
        } catch {
            return []
        }
    }

    internal static func parse(output: String) -> [RuntimeVersion] {
        var versions: [RuntimeVersion] = []
        let lines = output.split(whereSeparator: { $0.isNewline })
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Line looks like: "stable-aarch64-apple-darwin (default)" or "1.75.0-x86_64-apple-darwin"
            let token = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
            versions.append(
                RuntimeVersion(
                    kind: .rust,
                    version: token,
                    releaseDate: nil,
                    downloadURL: nil,
                    isLTS: false,
                    arch: nil
                )
            )
        }
        return versions
    }
}
