import Foundation

/// A single search hit that can be shown in the global search palette.
public struct SearchHit: Identifiable, Hashable {
    public enum Source: String, Hashable {
        case brew
        case maven
        case go
        case node
    }

    public let id: String
    public let source: Source
    public let title: String
    public let subtitle: String?

    public init(source: Source, title: String, subtitle: String?) {
        self.id = "\(source.rawValue):\(title)"
        self.source = source
        self.title = title
        self.subtitle = subtitle
    }
}

/// Aggregates lightweight, filterable data from the various package
/// managers so the global search palette can query them in one place.
///
/// The heavy scans (Maven / Go / npm) are performed lazily on first
/// query and then cached in-memory for the lifetime of the aggregator.
@MainActor
public final class SearchAggregator: ObservableObject {
    public static let shared = SearchAggregator()

    private let brewService: HomebrewService
    private let mavenService: MavenLocalRepositoryService
    private let goService: GoLocalCacheService
    private let npmService: NpmService

    private var brewHits: [SearchHit]?
    private var mavenHits: [SearchHit]?
    private var goHits: [SearchHit]?
    private var npmHits: [SearchHit]?

    public init(
        brewService: HomebrewService = DefaultHomebrewService(),
        mavenService: MavenLocalRepositoryService = DefaultMavenLocalRepositoryService(),
        goService: GoLocalCacheService = DefaultGoLocalCacheService(),
        npmService: NpmService = DefaultNpmService()
    ) {
        self.brewService = brewService
        self.mavenService = mavenService
        self.goService = goService
        self.npmService = npmService
    }

    /// Drop every cached corpus so the next `search()` re-scans.
    public func invalidate() {
        brewHits = nil
        mavenHits = nil
        goHits = nil
        npmHits = nil
    }

    /// Perform a case-insensitive contains search across every source.
    /// Results are capped per-source to keep the palette snappy.
    public func search(_ query: String, limitPerSource: Int = 25) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        async let brew = corpus(.brew)
        async let maven = corpus(.maven)
        async let go = corpus(.go)
        async let npm = corpus(.node)

        let all = await [brew, maven, go, npm]
        let needle = trimmed.lowercased()

        var results: [SearchHit] = []
        results.reserveCapacity(limitPerSource * 4)
        for corpus in all {
            var takenFromSource = 0
            for hit in corpus where takenFromSource < limitPerSource {
                if hit.title.lowercased().contains(needle) ||
                    (hit.subtitle?.lowercased().contains(needle) ?? false) {
                    results.append(hit)
                    takenFromSource += 1
                }
            }
        }
        return results
    }

    private func corpus(_ source: SearchHit.Source) async -> [SearchHit] {
        switch source {
        case .brew:
            if let cached = brewHits { return cached }
            let hits = await loadBrew()
            brewHits = hits
            return hits
        case .maven:
            if let cached = mavenHits { return cached }
            let hits = await loadMaven()
            mavenHits = hits
            return hits
        case .go:
            if let cached = goHits { return cached }
            let hits = await loadGo()
            goHits = hits
            return hits
        case .node:
            if let cached = npmHits { return cached }
            let hits = await loadNpm()
            npmHits = hits
            return hits
        }
    }

    private func loadBrew() async -> [SearchHit] {
        do {
            let inv = try await brewService.inventory(forceRefresh: false)
            let items = inv.formulae + inv.casks
            return items.map { pkg in
                SearchHit(source: .brew,
                          title: pkg.name,
                          subtitle: pkg.installedVersion ?? pkg.description)
            }
        } catch {
            return []
        }
    }

    private func loadMaven() async -> [SearchHit] {
        let svc = mavenService
        return await Task.detached(priority: .utility) { () -> [SearchHit] in
            let artifacts = (try? svc.scan()) ?? []
            return artifacts.map {
                SearchHit(source: .maven,
                          title: "\($0.groupId):\($0.artifactId)",
                          subtitle: $0.versions.first?.version)
            }
        }.value
    }

    private func loadGo() async -> [SearchHit] {
        let svc = goService
        return await Task.detached(priority: .utility) { () -> [SearchHit] in
            let modules = (try? svc.scan()) ?? []
            return modules.map {
                SearchHit(source: .go,
                          title: $0.modulePath,
                          subtitle: $0.versions.first?.version)
            }
        }.value
    }

    private func loadNpm() async -> [SearchHit] {
        guard await npmService.isNpmAvailable() else { return [] }
        do {
            let packages = try await npmService.listGlobalPackages()
            return packages.map {
                SearchHit(source: .node,
                          title: $0.name,
                          subtitle: $0.version)
            }
        } catch {
            return []
        }
    }
}
