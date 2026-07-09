import Foundation

public struct JavaProvider: VersionProvider {
    public let kind: RuntimeKind = .java
    private let session: URLSession
    private let featureVersions: [Int]

    public init(session: URLSession = .shared,
                featureVersions: [Int] = [8, 11, 17, 21]) {
        self.session = session
        self.featureVersions = featureVersions
    }

    public func listAvailable() async throws -> [RuntimeVersion] {
        let arch = Self.currentArch()
        var combined: [RuntimeVersion] = []
        for feature in featureVersions {
            let urlStr = "https://api.adoptium.net/v3/assets/feature_releases/\(feature)/ga?architecture=\(arch)&heap_size=normal&image_type=jdk&os=mac&vendor=eclipse&page_size=10&page=0"
            guard let url = URL(string: urlStr) else { continue }
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("EnvMatrix", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    // Skip this feature version but keep others
                    continue
                }
                let versions = try Self.decode(data: data, arch: arch)
                combined.append(contentsOf: versions)
            } catch is RuntimeServiceError {
                continue
            } catch {
                continue
            }
        }
        return combined
    }

    static func currentArch() -> String {
        #if arch(arm64)
        return "aarch64"
        #else
        return "x64"
        #endif
    }

    internal static func decode(data: Data, arch: String) throws -> [RuntimeVersion] {
        do {
            let releases = try JSONDecoder().decode([AdoptiumRelease].self, from: data)
            var results: [RuntimeVersion] = []
            for release in releases {
                let versionString: String = release.version_data?.semver
                    ?? release.version_data?.openjdk_version
                    ?? release.release_name
                // find first archive binary
                let binary = release.binaries.first { $0.package?.link != nil }
                let url = binary?.package?.link.flatMap(URL.init(string:))
                results.append(
                    RuntimeVersion(
                        kind: .java,
                        version: versionString,
                        releaseDate: parseDate(release.updated_at),
                        downloadURL: url,
                        isLTS: true,
                        arch: arch
                    )
                )
            }
            return results
        } catch {
            throw RuntimeServiceError.decoding("JavaProvider decode failed: \(error)")
        }
    }

    private static func parseDate(_ str: String?) -> Date? {
        guard let str = str else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: str)
    }
}

struct AdoptiumRelease: Decodable {
    let release_name: String
    let updated_at: String?
    let version_data: AdoptiumVersionData?
    let binaries: [AdoptiumBinary]
}

struct AdoptiumVersionData: Decodable {
    let semver: String?
    let openjdk_version: String?
}

struct AdoptiumBinary: Decodable {
    let package: AdoptiumPackage?
}

struct AdoptiumPackage: Decodable {
    let link: String?
}
