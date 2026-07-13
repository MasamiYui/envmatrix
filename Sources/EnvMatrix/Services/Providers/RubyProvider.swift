import Foundation

public struct RubyProvider: VersionProvider {
    public let kind: RuntimeKind = .ruby
    private let session: URLSession
    private let indexURL: URL

    public init(session: URLSession = .shared,
                indexURL: URL = URL(string: "https://cache.ruby-lang.org/pub/ruby/index.txt")!) {
        self.session = session
        self.indexURL = indexURL
    }

    public func listAvailable() async throws -> [RuntimeVersion] {
        let (data, response) = try await session.data(from: indexURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RuntimeServiceError.network("Ruby index returned \(http.statusCode)")
        }
        return try Self.decode(data: data)
    }

    internal static func decode(data: Data) throws -> [RuntimeVersion] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw RuntimeServiceError.decoding("RubyProvider: invalid UTF-8 payload")
        }
        do {
            let regex = try NSRegularExpression(
                pattern: #"ruby-(\d+\.\d+\.\d+)\.tar\.gz"#
            )
            var seen = Set<String>()
            var versions: [String] = []
            for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                let str = String(line)
                let range = NSRange(str.startIndex..<str.endIndex, in: str)
                guard let match = regex.firstMatch(in: str, range: range),
                      match.numberOfRanges >= 2,
                      let versionRange = Range(match.range(at: 1), in: str) else { continue }
                let version = String(str[versionRange])
                if seen.insert(version).inserted {
                    versions.append(version)
                }
            }
            let sorted = versions.sorted(by: Self.semverDescending)
            let top = Array(sorted.prefix(30))
            return top.compactMap { version in
                let components = version.split(separator: ".")
                guard components.count >= 2 else { return nil }
                let minor = "\(components[0]).\(components[1])"
                let urlString = "https://cache.ruby-lang.org/pub/ruby/\(minor)/ruby-\(version).tar.gz"
                let url = URL(string: urlString)
                return RuntimeVersion(
                    kind: .ruby,
                    version: version,
                    downloadURL: url,
                    isLTS: false,
                    arch: nil
                )
            }
        } catch let err as RuntimeServiceError {
            throw err
        } catch {
            throw RuntimeServiceError.decoding("RubyProvider decode failed: \(error)")
        }
    }

    internal static func semverDescending(_ lhs: String, _ rhs: String) -> Bool {
        let lc = lhs.split(separator: ".").compactMap { Int($0) }
        let rc = rhs.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(lc.count, rc.count) {
            let a = i < lc.count ? lc[i] : 0
            let b = i < rc.count ? rc[i] : 0
            if a != b { return a > b }
        }
        return false
    }
}
