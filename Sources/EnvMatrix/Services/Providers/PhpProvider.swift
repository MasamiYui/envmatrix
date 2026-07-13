import Foundation

public struct PhpProvider: VersionProvider {
    public let kind: RuntimeKind = .php
    private let session: URLSession
    private let indexURL: URL

    public init(session: URLSession = .shared,
                indexURL: URL = URL(string: "https://www.php.net/releases/index.php?json&max=30")!) {
        self.session = session
        self.indexURL = indexURL
    }

    public func listAvailable() async throws -> [RuntimeVersion] {
        let (data, response) = try await session.data(from: indexURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RuntimeServiceError.network("PHP releases returned \(http.statusCode)")
        }
        return try Self.decode(data: data)
    }

    internal static func decode(data: Data) throws -> [RuntimeVersion] {
        do {
            let decoder = JSONDecoder()
            let branches = try decoder.decode([String: PhpBranch].self, from: data)
            let versions = branches.values.map { $0.version }
            let sorted = versions.sorted(by: RubyProvider.semverDescending)
            let top = Array(sorted.prefix(30))
            return top.map { version in
                let urlString = "https://www.php.net/distributions/php-\(version).tar.gz"
                return RuntimeVersion(
                    kind: .php,
                    version: version,
                    downloadURL: URL(string: urlString),
                    isLTS: false,
                    arch: nil
                )
            }
        } catch let err as RuntimeServiceError {
            throw err
        } catch {
            throw RuntimeServiceError.decoding("PhpProvider decode failed: \(error)")
        }
    }
}

struct PhpBranch: Decodable {
    let version: String
    let date: String?
}
