import Foundation

/// A single search hit that can be shown in the global search palette.
public struct SearchHit: Identifiable, Hashable {
    public enum Source: String, Hashable, CaseIterable {
        case brew
        case maven
        case go
        case node
        case python
        case containerContext
        case containerImage
        case containerInstance
    }

    public let id: String
    public let source: Source
    public let title: String
    public let subtitle: String?
    public let keywords: String?

    public init(source: Source, title: String, subtitle: String?, keywords: String? = nil) {
        self.id = "\(source.rawValue):\(title):\(keywords ?? "")"
        self.source = source
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
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
    private let dockerService: DockerContextService
    private let podmanService: PodmanContextService
    private let dockerImageService: DockerImageService
    private let podmanImageService: PodmanImageService
    private let dockerContainerService: DockerContainerService
    private let podmanContainerService: PodmanContainerService
    private let ttl: TimeInterval

    private var cache: [SearchHit.Source: CacheEntry] = [:]
    private var invalidationObserver: NSObjectProtocol?

    public init(
        brewService: HomebrewService = DefaultHomebrewService(),
        mavenService: MavenLocalRepositoryService = DefaultMavenLocalRepositoryService(),
        goService: GoLocalCacheService = DefaultGoLocalCacheService(),
        npmService: NpmService = DefaultNpmService(),
        pipService: PipService = DefaultPipService(),
        dockerService: DockerContextService = DefaultDockerContextService(),
        podmanService: PodmanContextService = DefaultPodmanContextService(),
        dockerImageService: DockerImageService = DefaultDockerImageService(),
        podmanImageService: PodmanImageService = DefaultPodmanImageService(),
        dockerContainerService: DockerContainerService = DefaultDockerContainerService(),
        podmanContainerService: PodmanContainerService = DefaultPodmanContainerService(),
        ttl: TimeInterval = SearchAggregator.defaultTTL
    ) {
        self.brewService = brewService
        self.mavenService = mavenService
        self.goService = goService
        self.npmService = npmService
        self.pipService = pipService
        self.dockerService = dockerService
        self.podmanService = podmanService
        self.dockerImageService = dockerImageService
        self.podmanImageService = podmanImageService
        self.dockerContainerService = dockerContainerService
        self.podmanContainerService = podmanContainerService
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
        async let containers = corpus(.containerContext)
        async let images = corpus(.containerImage)
        async let instances = corpus(.containerInstance)

        let all = await [brew, maven, go, npm, pip, containers, images, instances]
        let needle = trimmed.lowercased()

        var results: [SearchHit] = []
        results.reserveCapacity(limitPerSource * all.count)
        for corpus in all {
            var takenFromSource = 0
            for hit in corpus where takenFromSource < limitPerSource {
                if hit.title.lowercased().contains(needle) ||
                    (hit.subtitle?.lowercased().contains(needle) ?? false) ||
                    (hit.keywords?.lowercased().contains(needle) ?? false) {
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
        case .containerContext: hits = await loadContainers()
        case .containerImage: hits = await loadContainerImages()
        case .containerInstance: hits = await loadContainerInstances()
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

    private func loadContainers() async -> [SearchHit] {
        async let dockerHits: [SearchHit] = {
            guard await dockerService.isDockerAvailable() else { return [] }
            do {
                let contexts = try await dockerService.listContexts()
                return contexts.map { ctx in
                    SearchHit(source: .containerContext,
                              title: "docker · \(ctx.name)",
                              subtitle: ctx.endpoint)
                }
            } catch {
                return []
            }
        }()
        async let podmanHits: [SearchHit] = {
            guard await podmanService.isPodmanAvailable() else { return [] }
            do {
                let conns = try await podmanService.listConnections()
                return conns.map { conn in
                    SearchHit(source: .containerContext,
                              title: "podman · \(conn.name)",
                              subtitle: conn.uri)
                }
            } catch {
                return []
            }
        }()
        let (d, p) = await (dockerHits, podmanHits)
        return d + p
    }

    private func loadContainerImages() async -> [SearchHit] {
        let dockerSvc = dockerImageService
        let podmanSvc = podmanImageService
        async let dockerImages: [ContainerImage] = {
            (try? await dockerSvc.list()) ?? []
        }()
        async let podmanImages: [ContainerImage] = {
            (try? await podmanSvc.list()) ?? []
        }()
        let (dockers, podmans) = await (dockerImages, podmanImages)
        let mapped = (dockers + podmans).map { img -> SearchHit in
            let repo = img.repository.isEmpty ? "<none>" : img.repository
            let tag = img.tag.isEmpty ? "<none>" : img.tag
            let title = "\(repo):\(tag)"
            let subtitle = img.engine == .docker ? "docker" : "podman"
            var kw = img.id
            if let digest = img.digest, !digest.isEmpty {
                kw += " \(digest)"
            }
            return SearchHit(source: .containerImage,
                             title: title,
                             subtitle: subtitle,
                             keywords: kw)
        }
        return mapped
    }

    private func loadContainerInstances() async -> [SearchHit] {
        let dockerSvc = dockerContainerService
        let podmanSvc = podmanContainerService
        async let dockerInstances: [ContainerInstance] = {
            (try? await dockerSvc.list(all: true)) ?? []
        }()
        async let podmanInstances: [ContainerInstance] = {
            (try? await podmanSvc.list(all: true)) ?? []
        }()
        let (dockers, podmans) = await (dockerInstances, podmanInstances)
        let mapped = (dockers + podmans).map { inst -> SearchHit in
            let title = inst.names.first ?? inst.id
            let subtitle = "\(inst.image) · \(inst.state.rawValue)"
            let kw = ([inst.id] + inst.names).joined(separator: " ")
            return SearchHit(source: .containerInstance,
                             title: title,
                             subtitle: subtitle,
                             keywords: kw)
        }
        return mapped
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
