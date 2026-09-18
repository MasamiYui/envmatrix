import Foundation

/// Download-mirror base URLs used by the Node and Go providers. Read from
/// UserDefaults so Settings › Mirror Sources and the one-click presets
/// actually change where archives are fetched from.
public enum DownloadMirrors {
    public static let nodeKey = "nodeMirror"
    public static let goKey = "goMirror"
    public static let nodeDefault = "https://nodejs.org/dist/"
    public static let goDefault = "https://go.dev/dl/"

    public static func nodeBase(defaults: UserDefaults = .standard) -> String {
        normalize(defaults.string(forKey: nodeKey), fallback: nodeDefault)
    }

    public static func goBase(defaults: UserDefaults = .standard) -> String {
        normalize(defaults.string(forKey: goKey), fallback: goDefault)
    }

    static func normalize(_ raw: String?, fallback: String) -> String {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
              s.hasPrefix("http://") || s.hasPrefix("https://") else { return fallback }
        if !s.hasSuffix("/") { s += "/" }
        return s
    }
}

/// A bundle of mirror choices applied across every ecosystem at once.
public enum MirrorPresetProfile: String, CaseIterable, Identifiable {
    case chinaMainland
    case official

    public var id: String { rawValue }

    public struct Values {
        public let npmRegistry: String
        public let pipIndex: String
        public let goProxy: String
        public let cargoRegistry: String
        public let gemSource: String
        public let composerRepository: String
        public let nugetSource: (name: String, url: String)
        public let uvIndex: String
        public let pnpmRegistry: String
        public let mavenMirror: MavenMirror?
        public let nodeDownload: String
        public let goDownload: String
    }

    public var values: Values {
        switch self {
        case .chinaMainland:
            return Values(
                npmRegistry: "https://registry.npmmirror.com",
                pipIndex: "https://pypi.tuna.tsinghua.edu.cn/simple",
                goProxy: "https://goproxy.cn,direct",
                cargoRegistry: "sparse+https://mirrors.ustc.edu.cn/crates.io-index/",
                gemSource: "https://gems.ruby-china.com/",
                composerRepository: "https://mirrors.aliyun.com/composer/",
                nugetSource: ("HuaweiCloud", "https://mirrors.huaweicloud.com/repository/nuget/v3/index.json"),
                uvIndex: "https://pypi.tuna.tsinghua.edu.cn/simple",
                pnpmRegistry: "https://registry.npmmirror.com",
                mavenMirror: MavenMirror(
                    mirrorId: "envmatrix-aliyun",
                    name: "Aliyun Public",
                    url: "https://maven.aliyun.com/repository/public",
                    mirrorOf: "*",
                    isEnabled: true
                ),
                nodeDownload: "https://npmmirror.com/mirrors/node/",
                goDownload: "https://mirrors.aliyun.com/golang/"
            )
        case .official:
            return Values(
                npmRegistry: "https://registry.npmjs.org/",
                pipIndex: "https://pypi.org/simple",
                goProxy: "https://proxy.golang.org,direct",
                cargoRegistry: "https://github.com/rust-lang/crates.io-index",
                gemSource: "https://rubygems.org/",
                composerRepository: "https://repo.packagist.org",
                nugetSource: ("nuget.org", "https://api.nuget.org/v3/index.json"),
                uvIndex: "https://pypi.org/simple",
                pnpmRegistry: "https://registry.npmjs.org/",
                mavenMirror: nil,
                nodeDownload: DownloadMirrors.nodeDefault,
                goDownload: DownloadMirrors.goDefault
            )
        }
    }
}

/// Outcome for one ecosystem after applying a preset.
public struct MirrorPresetResult: Identifiable, Hashable {
    public enum Ecosystem: String, CaseIterable {
        case npm, pip, go, cargo, gem, composer, nuget, uv, pnpm, maven, nodeDownload, goDownload
    }
    public enum Status: Hashable {
        case applied(String)
        case skipped(String)
        case failed(String)
    }

    public let ecosystem: Ecosystem
    public let status: Status
    public var id: String { ecosystem.rawValue }

    public var isApplied: Bool { if case .applied = status { return true } else { return false } }
}

/// Applies a `MirrorPresetProfile` to every ecosystem whose config can be
/// written. File-based configs are always written; CLI-based ones (go env,
/// composer, dotnet nuget) are skipped when the tool is absent.
public final class MirrorPresetApplier {
    private let npmrc: NpmrcService
    private let pip: PipConfService
    private let goEnv: GoEnvService
    private let cargo: CargoConfigService
    private let gem: GemConfigService
    private let composer: ComposerService
    private let nuget: NuGetService
    private let uv: UvConfigService
    private let pnpm: PnpmConfigService
    private let maven: MavenSettingsService
    private let defaults: UserDefaults

    public init(
        npmrc: NpmrcService = DefaultNpmrcService(),
        pip: PipConfService = DefaultPipConfService(),
        goEnv: GoEnvService = DefaultGoEnvService(),
        cargo: CargoConfigService = DefaultCargoConfigService(),
        gem: GemConfigService = DefaultGemConfigService(),
        composer: ComposerService = DefaultComposerService(),
        nuget: NuGetService = DefaultNuGetService(),
        uv: UvConfigService = DefaultUvConfigService(),
        pnpm: PnpmConfigService = DefaultPnpmConfigService(),
        maven: MavenSettingsService = DefaultMavenSettingsService(),
        defaults: UserDefaults = .standard
    ) {
        self.npmrc = npmrc
        self.pip = pip
        self.goEnv = goEnv
        self.cargo = cargo
        self.gem = gem
        self.composer = composer
        self.nuget = nuget
        self.uv = uv
        self.pnpm = pnpm
        self.maven = maven
        self.defaults = defaults
    }

    public func apply(_ profile: MirrorPresetProfile) async -> [MirrorPresetResult] {
        let v = profile.values
        var results: [MirrorPresetResult] = []

        results.append(fileWrite(.npm, v.npmRegistry) { try npmrc.writeRegistry(v.npmRegistry) })
        results.append(fileWrite(.pip, v.pipIndex) { try pip.writeIndexURL(v.pipIndex) })
        results.append(fileWrite(.cargo, v.cargoRegistry) { try cargo.writeRegistry(v.cargoRegistry) })
        results.append(fileWrite(.gem, v.gemSource) { try gem.writeSource(v.gemSource) })
        results.append(fileWrite(.uv, v.uvIndex) { try uv.setRegistry(url: v.uvIndex) })
        results.append(fileWrite(.pnpm, v.pnpmRegistry) { try pnpm.setRegistry(url: v.pnpmRegistry) })
        results.append(applyMaven(v.mavenMirror))

        if await goEnv.isGoAvailable() {
            results.append(await cliWrite(.go, v.goProxy) { try await goEnv.writeProxy(v.goProxy) })
        } else {
            results.append(.init(ecosystem: .go, status: .skipped("go not on PATH")))
        }
        if await composer.isComposerAvailable() {
            results.append(await cliWrite(.composer, v.composerRepository) {
                try await composer.writeRepository(v.composerRepository)
            })
        } else {
            results.append(.init(ecosystem: .composer, status: .skipped("composer not on PATH")))
        }
        if await nuget.isDotnetAvailable() {
            results.append(await cliWrite(.nuget, v.nugetSource.url) {
                try await nuget.setPrimarySource(name: v.nugetSource.name, url: v.nugetSource.url)
            })
        } else {
            results.append(.init(ecosystem: .nuget, status: .skipped("dotnet not on PATH")))
        }

        defaults.set(v.nodeDownload, forKey: DownloadMirrors.nodeKey)
        results.append(.init(ecosystem: .nodeDownload, status: .applied(v.nodeDownload)))
        defaults.set(v.goDownload, forKey: DownloadMirrors.goKey)
        results.append(.init(ecosystem: .goDownload, status: .applied(v.goDownload)))

        NotificationCenter.default.post(name: .envMatrixSearchCorpusInvalidated, object: nil)
        return results
    }

    private func fileWrite(_ eco: MirrorPresetResult.Ecosystem, _ value: String, _ op: () throws -> Void) -> MirrorPresetResult {
        do {
            try op()
            return .init(ecosystem: eco, status: .applied(value))
        } catch {
            return .init(ecosystem: eco, status: .failed(error.localizedDescription))
        }
    }

    private func cliWrite(_ eco: MirrorPresetResult.Ecosystem, _ value: String, _ op: () async throws -> Void) async -> MirrorPresetResult {
        do {
            try await op()
            return .init(ecosystem: eco, status: .applied(value))
        } catch {
            return .init(ecosystem: eco, status: .failed(error.localizedDescription))
        }
    }

    /// Official profile removes EnvMatrix-added mirrors; the China profile
    /// adds (or re-enables) the Aliyun mirror and disables other "*" mirrors.
    private func applyMaven(_ mirror: MavenMirror?) -> MirrorPresetResult {
        do {
            var settings = try maven.read()
            if let mirror {
                if let idx = settings.mirrors.firstIndex(where: { $0.mirrorId == mirror.mirrorId }) {
                    settings.mirrors[idx].isEnabled = true
                    settings.mirrors[idx].url = mirror.url
                } else {
                    settings.mirrors.append(mirror)
                }
                for i in settings.mirrors.indices where settings.mirrors[i].mirrorId != mirror.mirrorId
                    && settings.mirrors[i].mirrorOf == "*" {
                    settings.mirrors[i].isEnabled = false
                }
                try maven.write(settings)
                return .init(ecosystem: .maven, status: .applied(mirror.url))
            } else {
                let before = settings.mirrors.count
                settings.mirrors.removeAll { $0.mirrorId.hasPrefix("envmatrix-") }
                if settings.mirrors.count == before {
                    return .init(ecosystem: .maven, status: .skipped("no EnvMatrix mirror configured"))
                }
                try maven.write(settings)
                return .init(ecosystem: .maven, status: .applied("removed EnvMatrix mirror"))
            }
        } catch {
            return .init(ecosystem: .maven, status: .failed(error.localizedDescription))
        }
    }
}
