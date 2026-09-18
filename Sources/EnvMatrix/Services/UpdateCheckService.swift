import Foundation

/// A published release on GitHub.
public struct AppRelease: Equatable {
    public let version: String      // "0.4.1" (leading "v" stripped)
    public let tag: String          // "v0.4.1"
    public let url: URL             // html_url of the release page
    public let notes: String?       // release body (Markdown), may be empty

    public init(version: String, tag: String, url: URL, notes: String?) {
        self.version = version
        self.tag = tag
        self.url = url
        self.notes = notes
    }
}

public enum UpdateCheckError: Error, LocalizedError {
    case network(String)
    case decoding

    public var errorDescription: String? {
        switch self {
        case .network(let msg): return "Update check failed: \(msg)"
        case .decoding: return "Update check failed: unexpected response"
        }
    }
}

/// Fetches the latest GitHub release for the project. Deliberately tiny:
/// no framework dependency, no auto-download. The UI decides whether the
/// result is newer than the running build and offers the release page.
public protocol UpdateCheckService {
    func fetchLatestRelease() async throws -> AppRelease
}

public final class GitHubUpdateCheckService: UpdateCheckService {
    public static let repository = "MasamiYui/envmatrix"
    public static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!

    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.github.com/repos/\(GitHubUpdateCheckService.repository)/releases/latest")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    public func fetchLatestRelease() async throws -> AppRelease {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EnvMatrix", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UpdateCheckError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateCheckError.network("GitHub returned \(http.statusCode)")
        }
        return try Self.decode(data)
    }

    struct Payload: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
    }

    static func decode(_ data: Data) throws -> AppRelease {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let url = URL(string: payload.html_url) else {
            throw UpdateCheckError.decoding
        }
        return AppRelease(
            version: SemanticVersion.normalize(payload.tag_name),
            tag: payload.tag_name,
            url: url,
            notes: payload.body
        )
    }
}

/// Minimal semantic-version comparison ("1.2.3", "v1.2", "0.4.0-beta.1").
/// Pre-release suffixes are ignored except that a pre-release of X is
/// considered older than the final X.
public enum SemanticVersion {
    public static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    /// True when `candidate` is strictly newer than `current`.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) > 0
    }

    /// Returns <0, 0 or >0.
    public static func compare(_ lhs: String, _ rhs: String) -> Int {
        let (lCore, lPre) = split(normalize(lhs))
        let (rCore, rPre) = split(normalize(rhs))
        let count = max(lCore.count, rCore.count)
        for i in 0..<count {
            let l = i < lCore.count ? lCore[i] : 0
            let r = i < rCore.count ? rCore[i] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        switch (lPre, rPre) {
        case (nil, nil): return 0
        case (nil, _): return 1      // final > pre-release
        case (_, nil): return -1
        case (let a?, let b?): return a == b ? 0 : (a < b ? -1 : 1)
        }
    }

    private static func split(_ s: String) -> ([Int], String?) {
        let parts = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts[0].split(separator: ".").map { Int($0.filter { $0.isNumber }) ?? 0 }
        let pre = parts.count > 1 ? String(parts[1]) : nil
        return (core, pre)
    }
}
