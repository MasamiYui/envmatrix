import Foundation

public struct DotnetProvider: VersionProvider {
    public let kind: RuntimeKind = .dotnet
    private let session: URLSession
    private let indexURL: URL

    public init(session: URLSession = .shared,
                indexURL: URL = URL(string: "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json")!) {
        self.session = session
        self.indexURL = indexURL
    }

    public func listAvailable() async throws -> [RuntimeVersion] {
        var request = URLRequest(url: indexURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("EnvMatrix", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw RuntimeServiceError.network(".NET releases-index returned \(http.statusCode)")
        }
        return try Self.decode(data: data)
    }

    internal static func decode(data: Data) throws -> [RuntimeVersion] {
        do {
            let root = try JSONDecoder().decode(DotnetIndex.self, from: data)
            var results: [RuntimeVersion] = []
            for entry in root.releasesIndex {
                guard let sdk = entry.latestSdk, !sdk.isEmpty else { continue }
                let isLTS = (entry.supportPhase ?? "").lowercased() == "active"
                results.append(
                    RuntimeVersion(
                        kind: .dotnet,
                        version: sdk,
                        downloadURL: nil,
                        isLTS: isLTS
                    )
                )
                if results.count >= 20 {
                    break
                }
            }
            return results
        } catch let err as RuntimeServiceError {
            throw err
        } catch {
            throw RuntimeServiceError.decoding("DotnetProvider decode failed: \(error)")
        }
    }
}

struct DotnetIndex: Decodable {
    let releasesIndex: [DotnetChannel]

    enum CodingKeys: String, CodingKey {
        case releasesIndex = "releases-index"
    }
}

struct DotnetChannel: Decodable {
    let channelVersion: String?
    let latestSdk: String?
    let latestRuntime: String?
    let supportPhase: String?

    enum CodingKeys: String, CodingKey {
        case channelVersion = "channel-version"
        case latestSdk = "latest-sdk"
        case latestRuntime = "latest-runtime"
        case supportPhase = "support-phase"
    }
}
