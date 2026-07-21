import Foundation

/// A single search hit that can be shown in the global search palette.
public struct SearchHit: Identifiable, Hashable {
    public enum Source: String, Hashable, CaseIterable {
        case brew
        case maven
        case go
        case node
        case python
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

/// Broadcast when any mutation (install, uninstall, cache clean, mirror
/// switch...) invalidates a specific corpus and search results should be
/// re-scanned on next open.
///
/// The `object` is a `SearchHit.Source` value; observers can filter on it.
public extension Notification.Name {
    static let envMatrixSearchCorpusInvalidated = Notification.Name("envmatrix.search.corpusInvalidated")
}

/// Aggregates lightweight, filterable data from the various package
/// managers so the global search palette can query them in one place.
///
/// Each corpus is cached with a TTL (default 5 minutes). Callers can also
/// post `envMatrixSearchCorpusInvalidated` after any mutation to drop a
/// specific source proactively.
@MainActor
public final class SearchAggregator: ObservableObject {
    public static let shared = SearchAggregator()

    /// How long a per-source corpus is considered fresh.
    public nonisolated static let defaultTTL: TimeInterval = 5 * 60

    private struct CacheEntry {
        let hits: [SearchHit]
        let storedAt: Date
    }

    private let brewService: HomebrewService
    private let mavenService: MavenLocalRepositoryService
    private let goService: GoLocalCacheService
    private let npmService: NpmService
    private let pipService: PipService
    private let ttl: TimeInterval

    private var cache: [SearchHit.Source: CacheEntry] = [:]
    private var invalidationObserver: NSObjectProtocol?

    public init(
        brewService: HomebrewService = DefaultHomebrewService(),
        mavenService: MavenLocalRepositoryService = DefaultMavenLocalRepositoryService(),
        goService: GoLocalCacheService = DefaultGoLocalCacheService(),
        npmService: NpmService = DefaultNpmService(),
        pipService: PipService = DefaultPipService(),
        ttl: TimeInterval = SearchAggregator.defaultTTL
    ) {
        self.brewService = brewService
        self.mavenService = mavenService
        self.goService = goService
        self.npmService = npmService
        self.pipService = pipService
        self.ttl = ttl
        subscribeToInvalidations()
    }

    deinit {
        if let observer = invalidationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Drop every cached corpus so the next `search()` re-scans.
    public func invalidate() {
        cache.removeAll()
    }

    /// Drop a single corpus. Safe to call from any actor via the
    /// `envMatrixSearchCorpusInvalidated` notification.
    public func invalidate(_ source: SearchHit.Source) {
        cache.removeValue(forKey: source)
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
        async let pip = corpus(.python)

        let all = await [brew, maven, go, npm, pip]
        let needle = trimmed.lowercased()

        var results: [SearchHit] = []
        results.reserveCapacity(limitPerSource * 5)
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

    // MARK: - Corpus loading

    private func corpus(_ source: SearchHit.Source) async -> [SearchHit] {
        if let entry = cache[source], Date().timeIntervalSince(entry.storedAt) < ttl {
            return entry.hits
        }
        let hits: [SearchHit]
        switch source {
        case .brew:   hits = await loadBrew()
        case .maven:  hits = await loadMaven()
        case .go:     hits = await loadGo()
        case .node:   hits = await loadNpm()
        case .python: hits = await loadPip()
        }
        cache[source] = CacheEntry(hits: hits, storedAt: Date())
        return hits
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

    private func loadPip() async -> [SearchHit] {
        guard await pipService.isPipAvailable() else { return [] }
        do {
            let packages = try await pipService.listUserPackages()
            return packages.map {
                SearchHit(source: .python,
                          title: $0.name,
                          subtitle: $0.version)
            }
        } catch {
            return []
        }
    }

    // MARK: - Invalidation wiring

    private func subscribeToInvalidations() {
        invalidationObserver = NotificationCenter.default.addObserver(
            forName: .envMatrixSearchCorpusInvalidated,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            Task { @MainActor in
                if let source = note.object as? SearchHit.Source {
                    self.invalidate(source)
                } else {
                    self.invalidate()
                }
            }
        }
    }
}
