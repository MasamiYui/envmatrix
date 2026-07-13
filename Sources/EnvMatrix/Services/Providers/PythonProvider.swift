import Foundation

public struct PythonProvider: VersionProvider {
    public let kind: RuntimeKind = .python
    private let session: URLSession
    private let releasesURL: URL

    public init(session: URLSession = .shared,
                releasesURL: URL = URL(string: "https://api.github.com/repos/astral-sh/python-build-standalone/releases?per_page=10")!) {
        self.session = session
        self.releasesURL = releasesURL
    }

    public func listAvailable() async throws -> [RuntimeVersion] {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EnvMatrix", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw RuntimeServiceError.network("GitHub returned \(http.statusCode)")
        }
        let arch = Self.currentArch()
        return try Self.decode(data: data, arch: arch)
    }

    static func currentArch() -> String {
        #if arch(arm64)
        return "aarch64"
        #else
        return "x86_64"
        #endif
    }

    internal static func decode(data: Data, arch: String) throws -> [RuntimeVersion] {
        do {
            let releases = try JSONDecoder().decode([PythonGHRelease].self, from: data)
            var results: [RuntimeVersion] = []
            let pattern = "cpython-"
            let suffix = "\(arch)-apple-darwin-install_only.tar.gz"
            for release in releases {
                for asset in release.assets {
                    guard asset.name.hasPrefix(pattern),
                          asset.name.hasSuffix(suffix) else { continue }
                    // asset.name: cpython-<ver>-<arch>-apple-darwin-install_only.tar.gz
                    let stripped = String(asset.name.dropFirst(pattern.count))
                    // find first '-' that separates version from arch
                    guard let versionEnd = stripped.range(of: "-\(arch)") else { continue }
                    let versionRaw = String(stripped[..<versionEnd.lowerBound])
                    // versionRaw might be like "3.12.1+20240107"
                    let version = versionRaw.split(separator: "+").first.map(String.init) ?? versionRaw
                    let url = URL(string: asset.browser_download_url)
                    results.append(
                        RuntimeVersion(
                            kind: .python,
                            version: version,
                            releaseDate: parseDate(release.published_at),
                            downloadURL: url,
                            isLTS: false,
                            arch: arch
                        )
                    )
                    if results.count >= 30 {
                        return results
                    }
                }
            }
            return results
        } catch let err as RuntimeServiceError {
            throw err
        } catch {
            throw RuntimeServiceError.decoding("PythonProvider decode failed: \(error)")
        }
    }

    private static func parseDate(_ str: String?) -> Date? {
        guard let str = str else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: str)
    }
}

struct PythonGHRelease: Decodable {
    let tag_name: String?
    let published_at: String?
    let assets: [PythonGHAsset]
}

struct PythonGHAsset: Decodable {
    let name: String
    let browser_download_url: String
}
