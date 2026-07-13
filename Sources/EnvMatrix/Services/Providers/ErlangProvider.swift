import Foundation

public struct ErlangProvider: VersionProvider {
    public let kind: RuntimeKind = .erlang
    private let session: URLSession
    private let indexURL: URL

    public init(session: URLSession = .shared,
                indexURL: URL = URL(string: "https://api.github.com/repos/erlang/otp/releases?per_page=30")!) {
        self.session = session
        self.indexURL = indexURL
    }

    public func listAvailable() async throws -> [RuntimeVersion] {
        var request = URLRequest(url: indexURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EnvMatrix", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw RuntimeServiceError.network("Erlang releases returned \(http.statusCode)")
        }
        return try Self.decode(data: data)
    }

    internal static func decode(data: Data) throws -> [RuntimeVersion] {
        do {
            let releases = try JSONDecoder().decode([ErlangGHRelease].self, from: data)
            var results: [RuntimeVersion] = []
            for release in releases {
                if release.draft == true { continue }
                if release.prerelease == true { continue }
                guard let version = extractVersion(from: release.tagName) else { continue }
                results.append(
                    RuntimeVersion(
                        kind: .erlang,
                        version: version,
                        downloadURL: nil,
                        isLTS: false
                    )
                )
            }
            return results
        } catch let err as RuntimeServiceError {
            throw err
        } catch {
            throw RuntimeServiceError.decoding("ErlangProvider decode failed: \(error)")
        }
    }

    private static func extractVersion(from tag: String) -> String? {
        let pattern = #"^OTP-(\d+(?:\.\d+){1,2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, range: range), match.numberOfRanges >= 2 else {
            return nil
        }
        guard let versionRange = Range(match.range(at: 1), in: tag) else {
            return nil
        }
        return String(tag[versionRange])
    }
}

fileprivate struct ErlangGHRelease: Decodable {
    let tagName: String
    let draft: Bool?
    let prerelease: Bool?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
    }
}
