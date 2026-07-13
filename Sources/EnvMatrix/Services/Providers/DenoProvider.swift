import Foundation

struct GHRelease: Decodable {
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
}

public struct DenoProvider: VersionProvider {
    public let kind: RuntimeKind = .deno
    private let session: URLSession
    private let indexURL: URL

    public init(session: URLSession = .shared,
                indexURL: URL = URL(
                    string: "https://api.github.com/repos/denoland/deno/releases?per_page=30"
                )!) {
        self.session = session
        self.indexURL = indexURL
    }

    public func listAvailable() async throws -> [RuntimeVersion] {
        let (data, response) = try await session.data(from: indexURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw RuntimeServiceError.network("Deno releases returned \(http.statusCode)")
        }
        return try Self.decode(data: data)
    }

    internal static func decode(data: Data) throws -> [RuntimeVersion] {
        do {
            let releases = try JSONDecoder().decode([GHRelease].self, from: data)
            var results: [RuntimeVersion] = []
            let pattern = #"^(\d+\.\d+\.\d+)(?:-[A-Za-z0-9.\-]+)?$"#
            let regex = try NSRegularExpression(pattern: pattern)
            for release in releases {
                if release.draft || release.prerelease { continue }
                var tag = release.tag_name
                if tag.hasPrefix("v") {
                    tag = String(tag.dropFirst())
                }
                let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
                guard let match = regex.firstMatch(in: tag, options: [], range: range),
                      match.numberOfRanges >= 2,
                      let coreRange = Range(match.range(at: 1), in: tag) else {
                    continue
                }
                let core = String(tag[coreRange])
                results.append(
                    RuntimeVersion(
                        kind: .deno,
                        version: core,
                        releaseDate: nil,
                        downloadURL: nil,
                        isLTS: false,
                        arch: nil
                    )
                )
            }
            return results
        } catch let err as RuntimeServiceError {
            throw err
        } catch {
            throw RuntimeServiceError.decoding("DenoProvider decode failed: \(error)")
        }
    }
}
