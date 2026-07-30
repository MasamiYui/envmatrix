import Foundation

struct KotlinGHRelease: Decodable {
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let published_at: String?
    let assets: [KotlinGHAsset]
}

struct KotlinGHAsset: Decodable {
    let name: String
    let browser_download_url: String
}

public struct KotlinProvider: VersionProvider {
    public let kind: RuntimeKind = .kotlin
    private let session: URLSession
    private let indexURL: URL

    public init(session: URLSession = .shared,
                indexURL: URL = URL(
                    string: "https://api.github.com/repos/JetBrains/kotlin/releases?per_page=30"
                )!) {
        self.session = session
        self.indexURL = indexURL
    }

    public func listAvailable() async throws -> [RuntimeVersion] {
        var request = URLRequest(url: indexURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EnvMatrix", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw RuntimeServiceError.network("Kotlin releases returned \(http.statusCode)")
        }
        return try Self.decode(data: data)
    }

    internal static func decode(data: Data) throws -> [RuntimeVersion] {
        do {
            let releases = try JSONDecoder().decode([KotlinGHRelease].self, from: data)
            let formatter = ISO8601DateFormatter()
            var results: [RuntimeVersion] = []
            for release in releases {
                if release.prerelease || release.draft { continue }
                guard let asset = release.assets.first(where: { asset in
                    asset.name.contains("kotlin-compiler-") && asset.name.hasSuffix(".zip")
                }) else {
                    continue
                }
                guard let downloadURL = URL(string: asset.browser_download_url) else {
                    continue
                }
                var versionString = release.tag_name
                if versionString.hasPrefix("v") {
                    versionString = String(versionString.dropFirst())
                }
                let releaseDate = release.published_at.flatMap { formatter.date(from: $0) }
                results.append(
                    RuntimeVersion(
                        kind: .kotlin,
                        version: versionString,
                        releaseDate: releaseDate,
                        downloadURL: downloadURL,
                        isLTS: false,
                        arch: "universal"
                    )
                )
            }
            return results
        } catch let err as RuntimeServiceError {
            throw err
        } catch {
            throw RuntimeServiceError.decoding("KotlinProvider decode failed: \(error)")
        }
    }
}
