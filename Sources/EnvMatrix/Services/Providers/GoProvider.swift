import Foundation

public struct GoProvider: VersionProvider {
    public let kind: RuntimeKind = .go
    private let session: URLSession
    private let indexURL: URL

    public init(session: URLSession = .shared,
                indexURL: URL = URL(string: "https://go.dev/dl/?mode=json&include=all")!) {
        self.session = session
        self.indexURL = indexURL
    }

    public func listAvailable() async throws -> [RuntimeVersion] {
        let (data, response) = try await session.data(from: indexURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw RuntimeServiceError.network("Go dl index returned \(http.statusCode)")
        }
        let arch = Self.currentArch()
        return try Self.decode(data: data, arch: arch)
    }

    static func currentArch() -> String {
        #if arch(arm64)
        return "arm64"
        #else
        return "amd64"
        #endif
    }

    internal static func decode(data: Data, arch: String) throws -> [RuntimeVersion] {
        do {
            let entries = try JSONDecoder().decode([GoRelease].self, from: data)
            var results: [RuntimeVersion] = []
            for entry in entries {
                let match = entry.files.first { file in
                    file.os == "darwin"
                        && file.arch == arch
                        && file.kind == "archive"
                }
                guard let match = match else { continue }
                let versionString = entry.version.hasPrefix("go")
                    ? String(entry.version.dropFirst(2))
                    : entry.version
                let urlString = "https://go.dev/dl/\(match.filename)"
                let url = URL(string: urlString)
                results.append(
                    RuntimeVersion(
                        kind: .go,
                        version: versionString,
                        releaseDate: nil,
                        downloadURL: url,
                        isLTS: entry.stable,
                        arch: arch
                    )
                )
                if results.count >= 30 {
                    break
                }
            }
            return results
        } catch let err as RuntimeServiceError {
            throw err
        } catch {
            throw RuntimeServiceError.decoding("GoProvider decode failed: \(error)")
        }
    }
}

struct GoRelease: Decodable {
    let version: String
    let stable: Bool
    let files: [GoFile]
}

struct GoFile: Decodable {
    let filename: String
    let os: String
    let arch: String
    let kind: String
    let sha256: String?
}
