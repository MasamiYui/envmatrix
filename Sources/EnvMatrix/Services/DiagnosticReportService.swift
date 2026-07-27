import Foundation
import AppKit

/// Assembles a human-readable Markdown snapshot of the current machine's
/// package-manager landscape. Intended to be attached to bug reports or
/// pasted into a chat when asking for help.
public struct DiagnosticReportService {
    private let brewService: HomebrewService
    private let mavenService: MavenLocalRepositoryService
    private let goService: GoLocalCacheService
    private let npmService: NpmService
    private let npmrcService: NpmrcService
    private let dockerService: DockerContextService
    private let podmanService: PodmanContextService
    private let dockerImageService: DockerImageService
    private let dockerContainerService: DockerContainerService
    private let podmanImageService: PodmanImageService
    private let podmanContainerService: PodmanContainerService

    public init(
        brewService: HomebrewService = DefaultHomebrewService(),
        mavenService: MavenLocalRepositoryService = DefaultMavenLocalRepositoryService(),
        goService: GoLocalCacheService = DefaultGoLocalCacheService(),
        npmService: NpmService = DefaultNpmService(),
        npmrcService: NpmrcService = DefaultNpmrcService(),
        dockerService: DockerContextService = DefaultDockerContextService(),
        podmanService: PodmanContextService = DefaultPodmanContextService(),
        dockerImageService: DockerImageService = DefaultDockerImageService(),
        dockerContainerService: DockerContainerService = DefaultDockerContainerService(),
        podmanImageService: PodmanImageService = DefaultPodmanImageService(),
        podmanContainerService: PodmanContainerService = DefaultPodmanContainerService()
    ) {
        self.brewService = brewService
        self.mavenService = mavenService
        self.goService = goService
        self.npmService = npmService
        self.npmrcService = npmrcService
        self.dockerService = dockerService
        self.podmanService = podmanService
        self.dockerImageService = dockerImageService
        self.dockerContainerService = dockerContainerService
        self.podmanImageService = podmanImageService
        self.podmanContainerService = podmanContainerService
    }

    /// Build the report. Safe to call from any actor; internally offloads
    /// I/O-heavy calls onto a detached task.
    public func makeReport() async -> String {
        var lines: [String] = []
        let now = ISO8601DateFormatter().string(from: Date())

        lines.append("# EnvMatrix Diagnostic Report")
        lines.append("")
        lines.append("- Generated: \(now)")
        lines.append("- OS: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        if let bundle = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            lines.append("- App version: \(bundle)")
        }
        lines.append("- Locale: \(Locale.current.identifier)")
        lines.append("- CPU cores: \(ProcessInfo.processInfo.processorCount)")
        lines.append("")

        // Homebrew
        lines.append("## Homebrew")
        if brewService.isAvailable {
            lines.append("- Binary: `\(brewService.brewPath)`")
            if let inv = try? await brewService.inventory(forceRefresh: false) {
                lines.append("- Formulae installed: \(inv.formulae.count)")
                lines.append("- Casks installed: \(inv.casks.count)")
                lines.append("- Outdated: \(inv.outdatedCount)")
                lines.append("- brew version: \(inv.brewVersion)")
            } else {
                lines.append("- Inventory: unavailable")
            }
        } else {
            lines.append("- Not detected on PATH")
        }
        lines.append("")

        // Maven
        let mavenBytes = await Task.detached(priority: .utility) { () -> Int64 in
            (try? self.mavenService.totalSize()) ?? 0
        }.value
        let mavenCount = await Task.detached(priority: .utility) { () -> Int in
            (try? self.mavenService.scan().count) ?? 0
        }.value
        lines.append("## Maven")
        lines.append("- Local repository size: \(formatBytes(mavenBytes))")
        lines.append("- Artifacts: \(mavenCount)")
        lines.append("")

        // Go
        let goBytes = await Task.detached(priority: .utility) { () -> Int64 in
            (try? self.goService.totalSize()) ?? 0
        }.value
        let goCount = await Task.detached(priority: .utility) { () -> Int in
            (try? self.goService.scan().count) ?? 0
        }.value
        lines.append("## Go modules")
        lines.append("- GOMODCACHE size: \(formatBytes(goBytes))")
        lines.append("- Modules cached: \(goCount)")
        lines.append("")

        // npm
        lines.append("## npm")
        let npmAvailable = await npmService.isNpmAvailable()
        if npmAvailable {
            let globalCount = (try? await npmService.listGlobalPackages().count) ?? 0
            let cache = try? await npmService.cacheStats()
            lines.append("- Global packages: \(globalCount)")
            if let cache = cache {
                lines.append("- Cache path: `\(cache.path)`")
                lines.append("- Cache size: \(formatBytes(cache.sizeBytes))")
            }
            if let registry = try? npmrcService.readRegistry() {
                let display = registry.isEmpty ? "(default)" : registry
                lines.append("- Registry: `\(display)`")
            }
        } else {
            lines.append("- npm not detected on PATH")
        }
        lines.append("")

        let dockerAvailable = await dockerService.isDockerAvailable()
        let podmanAvailable = await podmanService.isPodmanAvailable()

        lines.append("## Container Contexts")
        if dockerAvailable {
            if let contexts = try? await dockerService.listContexts() {
                let current = contexts.first(where: { $0.isCurrent })
                lines.append("- Docker current: `\(current?.name ?? "(none)")`")
                if let current, !current.endpoint.isEmpty {
                    lines.append("- Docker endpoint: `\(current.endpoint)`")
                }
                lines.append("- Docker contexts: \(contexts.count)")
            } else {
                lines.append("- Docker: available but list failed")
            }
        } else {
            lines.append("- Docker not detected on PATH")
        }
        if podmanAvailable {
            if let conns = try? await podmanService.listConnections() {
                let def = conns.first(where: { $0.isDefault })
                lines.append("- Podman default: `\(def?.name ?? "(none)")`")
                if let def, !def.uri.isEmpty {
                    lines.append("- Podman URI: `\(def.uri)`")
                }
                lines.append("- Podman connections: \(conns.count)")
            } else {
                lines.append("- Podman: available but list failed")
            }
        } else {
            lines.append("- Podman not detected on PATH")
        }
        lines.append("")

        appendImagesSection(&lines, dockerAvailable: dockerAvailable, podmanAvailable: podmanAvailable, dockerImages: await loadDockerImages(available: dockerAvailable), podmanImages: await loadPodmanImages(available: podmanAvailable))
        appendInstancesSection(&lines, dockerAvailable: dockerAvailable, podmanAvailable: podmanAvailable, dockerInstances: await loadDockerInstances(available: dockerAvailable), podmanInstances: await loadPodmanInstances(available: podmanAvailable))

        lines.append("---")
        lines.append("_Generated by EnvMatrix. Feel free to attach this to an issue._")
        return lines.joined(separator: "\n")
    }

    private func loadDockerImages(available: Bool) async -> [ContainerImage]? {
        guard available else { return nil }
        return try? await dockerImageService.list()
    }

    private func loadPodmanImages(available: Bool) async -> [ContainerImage]? {
        guard available else { return nil }
        return try? await podmanImageService.list()
    }

    private func loadDockerInstances(available: Bool) async -> [ContainerInstance]? {
        guard available else { return nil }
        return try? await dockerContainerService.list(all: false)
    }

    private func loadPodmanInstances(available: Bool) async -> [ContainerInstance]? {
        guard available else { return nil }
        return try? await podmanContainerService.list(all: false)
    }

    private func appendImagesSection(
        _ lines: inout [String],
        dockerAvailable: Bool,
        podmanAvailable: Bool,
        dockerImages: [ContainerImage]?,
        podmanImages: [ContainerImage]?
    ) {
        lines.append("## Container Images (top 20 by size)")
        var noteAppended = false
        if !dockerAvailable || dockerImages == nil {
            lines.append("- [docker] _(unavailable)_")
            noteAppended = true
        }
        if !podmanAvailable || podmanImages == nil {
            lines.append("- [podman] _(unavailable)_")
            noteAppended = true
        }
        var combined: [ContainerImage] = []
        if let dockerImages { combined.append(contentsOf: dockerImages) }
        if let podmanImages { combined.append(contentsOf: podmanImages) }
        let sorted = combined.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(20)
        for image in sorted {
            lines.append("- \(formatImageLine(image))")
        }
        if sorted.isEmpty && !noteAppended {
            lines.append("- _(no images)_")
        }
        lines.append("")
    }

    private func appendInstancesSection(
        _ lines: inout [String],
        dockerAvailable: Bool,
        podmanAvailable: Bool,
        dockerInstances: [ContainerInstance]?,
        podmanInstances: [ContainerInstance]?
    ) {
        lines.append("## Container Instances (running only)")
        var noteAppended = false
        if !dockerAvailable || dockerInstances == nil {
            lines.append("- [docker] _(unavailable)_")
            noteAppended = true
        }
        if !podmanAvailable || podmanInstances == nil {
            lines.append("- [podman] _(unavailable)_")
            noteAppended = true
        }
        var combined: [ContainerInstance] = []
        if let dockerInstances { combined.append(contentsOf: dockerInstances) }
        if let podmanInstances { combined.append(contentsOf: podmanInstances) }
        let running = combined.filter { $0.state == .running }.sorted { $0.createdAt > $1.createdAt }
        for instance in running {
            lines.append("- \(formatInstanceLine(instance))")
        }
        if running.isEmpty && !noteAppended {
            lines.append("- _(no running containers)_")
        }
        lines.append("")
    }

    private func formatImageLine(_ image: ContainerImage) -> String {
        let engineTag = image.engine == .docker ? "[docker]" : "[podman]"
        let repo = image.repository.isEmpty ? "<none>" : image.repository
        let tag = image.tag.isEmpty ? "<none>" : image.tag
        let size = formatBytes(image.sizeBytes)
        let dateStr = shortDate(image.createdAt)
        return "\(engineTag) \(repo):\(tag)  (\(size), \(dateStr))"
    }

    private func formatInstanceLine(_ instance: ContainerInstance) -> String {
        let engineTag = instance.engine == .docker ? "[docker]" : "[podman]"
        let name = instance.names.first ?? instance.id
        let status = instance.status.isEmpty ? instance.state.rawValue : instance.status
        return "\(engineTag) \(name)  \(instance.image)  \(status)"
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useMB, .useGB, .useKB, .useBytes]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: bytes)
    }
}
