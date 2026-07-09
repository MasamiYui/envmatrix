import Foundation

public struct NodeProvider: VersionProvider {
    public let kind: RuntimeKind = .node
    private let session: URLSession
    private let indexURL: URL

    public init(session: URLSession = .shared,
                indexURL: URL = URL(string: "https://nodejs.org/dist/index.json")!) {
        self.session = session
        self.indexURL = indexURL
    }

    public func listAvailable() async throws -> [RuntimeVersion] {
        let (data, response) = try await session.data(from: indexURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw RuntimeServiceError.network("Node index returned \(http.statusCode)")
        }
        let arch = Self.currentArch()
        return try Self.decode(data: data, arch: arch)
    }

    static func currentArch() -> String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x64"
        #endif
    }

    internal static func decode(data: Data, arch: String) throws -> [RuntimeVersion] {
        do {
            let entries = try JSONDecoder().decode([NodeIndexEntry].self, from: data)
            let targetFile = "osx-\(arch)-tar"
            let altFile = "darwin-\(arch)-tar"
            var results: [RuntimeVersion] = []
            for entry in entries {
                let matches = entry.files.contains(targetFile) || entry.files.contains(altFile)
                guard matches else { continue }
                let versionString = entry.version.hasPrefix("v")
                    ? String(entry.version.dropFirst())
                    : entry.version
                let urlString = "https://nodejs.org/dist/\(entry.version)/node-\(entry.version)-darwin-\(arch).tar.gz"
                let url = URL(string: urlString)
                let isLTS: Bool
                switch entry.lts {
                case .bool(let b): isLTS = b
                case .string: isLTS = true
                case .none: isLTS = false
                }
                results.append(
                    RuntimeVersion(
                        kind: .node,
                        version: versionString,
                        releaseDate: parseDate(entry.date),
                        downloadURL: url,
                        isLTS: isLTS,
                        arch: arch
                    )
                )
            }
            return results
        } catch let err as RuntimeServiceError {
            throw err
        } catch {
            throw RuntimeServiceError.decoding("NodeProvider decode failed: \(error)")
        }
    }

    private static func parseDate(_ str: String?) -> Date? {
        guard let str = str else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: str)
    }
}

struct NodeIndexEntry: Decodable {
    let version: String
    let date: String?
    let files: [String]
    let lts: LTSValue?

    enum LTSValue: Decodable {
        case bool(Bool)
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let b = try? container.decode(Bool.self) {
                self = .bool(b)
                return
            }
            if let s = try? container.decode(String.self) {
                self = .string(s)
                return
            }
            throw DecodingError.typeMismatch(
                LTSValue.self,
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "Expected Bool or String for lts")
            )
        }
    }
}
