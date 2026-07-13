import Foundation

public struct BunProvider: VersionProvider {
    public let kind: RuntimeKind = .bun
    private let session: URLSession
    private let indexURL: URL

    public init(session: URLSession = .shared,
                indexURL: URL = URL(
                    string: "https://api.github.com/repos/oven-sh/bun/releases?per_page=30"
                )!) {
        self.session = session
        self.indexURL = indexURL
    }

    public func listAvailable() async throws -> [RuntimeVersion] {
        let (data, response) = try await session.data(from: indexURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw RuntimeServiceError.network("Bun releases returned \(http.statusCode)")
        }
        return try Self.decode(data: data)
    }

    internal static func decode(data: Data) throws -> [RuntimeVersion] {
        do {
            let releases = try JSONDecoder().decode([GHRelease].self, from: data)
            var results: [RuntimeVersion] = []
            let pattern = #"^bun-v(\d+\.\d+\.\d+)$"#
            let regex = try NSRegularExpression(pattern: pattern)
            for release in releases {
                if release.draft || release.prerelease { continue }
                let tag = release.tag_name
                let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
                guard let match = regex.firstMatch(in: tag, options: [], range: range),
                      match.numberOfRanges >= 2,
                      let coreRange = Range(match.range(at: 1), in: tag) else {
                    continue
                }
                let core = String(tag[coreRange])
                results.append(
                    RuntimeVersion(
                        kind: .bun,
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
            throw RuntimeServiceError.decoding("BunProvider decode failed: \(error)")
        }
    }
}
