import XCTest
@testable import EnvMatrix

final class MirrorPresetTests: XCTestCase {
    func testDownloadMirrorNormalization() {
        XCTAssertEqual(DownloadMirrors.normalize(nil, fallback: "https://x/"), "https://x/")
        XCTAssertEqual(DownloadMirrors.normalize("", fallback: "https://x/"), "https://x/")
        XCTAssertEqual(DownloadMirrors.normalize("ftp://bad", fallback: "https://x/"), "https://x/")
        XCTAssertEqual(DownloadMirrors.normalize("https://npmmirror.com/mirrors/node", fallback: "https://x/"),
                       "https://npmmirror.com/mirrors/node/")
    }

    func testProvidersHonourDownloadMirrorDefaults() throws {
        let suite = "envmatrix-mirror-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("https://npmmirror.com/mirrors/node/", forKey: DownloadMirrors.nodeKey)
        XCTAssertEqual(DownloadMirrors.nodeBase(defaults: defaults), "https://npmmirror.com/mirrors/node/")
        XCTAssertEqual(DownloadMirrors.goBase(defaults: defaults), DownloadMirrors.goDefault)
    }

    func testProfilesAreComplete() {
        for profile in MirrorPresetProfile.allCases {
            let v = profile.values
            for url in [v.npmRegistry, v.pipIndex, v.goProxy, v.cargoRegistry, v.gemSource,
                        v.composerRepository, v.nugetSource.url, v.uvIndex, v.pnpmRegistry,
                        v.nodeDownload, v.goDownload] {
                XCTAssertFalse(url.isEmpty, "\(profile) has an empty value")
            }
        }
        XCTAssertNotNil(MirrorPresetProfile.chinaMainland.values.mavenMirror)
        XCTAssertNil(MirrorPresetProfile.official.values.mavenMirror)
    }

    // MARK: - Applier with in-memory services

    private final class MemNpmrc: NpmrcService {
        var npmrcURL = URL(fileURLWithPath: "/tmp/.npmrc")
        var written: String?
        func readRegistry() throws -> String { written ?? "" }
        func writeRegistry(_ url: String) throws { written = url }
        func presetMirrors() -> [NodeRegistryMirror] { [] }
    }
    private final class MemPip: PipConfService {
        var pipConfURL = URL(fileURLWithPath: "/tmp/pip.conf")
        var written: String?
        func readIndexURL() throws -> String { written ?? "" }
        func writeIndexURL(_ url: String) throws { written = url }
        func presetMirrors() -> [PythonIndexMirror] { [] }
    }
    private final class MemGo: GoEnvService {
        var available = false
        var written: String?
        func readProxy() async throws -> String { written ?? "" }
        func writeProxy(_ value: String) async throws { written = value }
        func isGoAvailable() async -> Bool { available }
        func presetProxies() -> [GoProxyPreset] { [] }
    }
    private final class MemCargo: CargoConfigService {
        var configURL = URL(fileURLWithPath: "/tmp/config.toml")
        var written: String?
        func readRegistry() throws -> String { written ?? "" }
        func writeRegistry(_ url: String) throws { written = url }
        func presetMirrors() -> [RustCrateRegistry] { [] }
    }
    private final class MemGem: GemConfigService {
        var gemrcURL = URL(fileURLWithPath: "/tmp/.gemrc")
        var written: String?
        func readSource() throws -> String { written ?? "" }
        func writeSource(_ url: String) throws { written = url }
        func presetMirrors() -> [RubyGemSource] { [] }
    }
    private final class FailingComposer: ComposerService {
        func isComposerAvailable() async -> Bool { true }
        func listGlobalPackages() async throws -> [ComposerGlobalPackage] { [] }
        func uninstallGlobal(_ name: String) async throws {}
        func cacheStats() async throws -> ComposerCacheStats { ComposerCacheStats(path: "", sizeBytes: 0) }
        func cacheClean() async throws {}
        func readRepository() async throws -> String { "" }
        func writeRepository(_ url: String) async throws { throw ComposerError.commandFailed("boom") }
        func presetMirrors() -> [ComposerRepositoryMirror] { [] }
    }
    private final class AbsentNuGet: NuGetService {
        func isDotnetAvailable() async -> Bool { false }
        func listGlobalTools() async throws -> [DotnetGlobalTool] { [] }
        func uninstallGlobalTool(_ name: String) async throws {}
        func cacheStats() async throws -> DotnetCacheStats { DotnetCacheStats(path: "", sizeBytes: 0) }
        func cacheClean() async throws {}
        func readEnabledSources() async throws -> [(name: String, url: String)] { [] }
        func setPrimarySource(name: String, url: String) async throws {}
        func presetMirrors() -> [NuGetSourceMirror] { [] }
    }
    private final class MemUv: UvConfigService {
        var uvConfigURL = URL(fileURLWithPath: "/tmp/uv.toml")
        var written: String?
        func currentRegistry() throws -> String { written ?? "" }
        func setRegistry(url: String) throws { written = url }
        func presetRegistries() -> [UvRegistryPreset] { [] }
    }
    private final class MemPnpm: PnpmConfigService {
        var npmrcURL = URL(fileURLWithPath: "/tmp/.npmrc")
        var written: String?
        func currentRegistry() throws -> String { written ?? "" }
        func setRegistry(url: String) throws { written = url }
        func presetRegistries() -> [PnpmRegistryPreset] { [] }
    }
    private final class MemMaven: MavenSettingsService {
        var settings = MavenSettings()
        var settingsURL = URL(fileURLWithPath: "/tmp/settings.xml")
        func read() throws -> MavenSettings { settings }
        func write(_ s: MavenSettings) throws { settings = s }
        func addMirror(_ mirror: MavenMirror) throws { settings.mirrors.append(mirror) }
        func updateMirror(_ mirror: MavenMirror) throws {}
        func deleteMirror(_ id: UUID) throws {}
        func backup() throws -> URL? { nil }
        func presetMirrors() -> [MavenMirror] { [] }
    }

    func testApplierWritesFilesSkipsAbsentToolsAndReportsFailures() async {
        let suite = "envmatrix-mirror-apply-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let npm = MemNpmrc(), pip = MemPip(), go = MemGo(), cargo = MemCargo(), gem = MemGem()
        let uv = MemUv(), pnpm = MemPnpm(), maven = MemMaven()
        let applier = MirrorPresetApplier(
            npmrc: npm, pip: pip, goEnv: go, cargo: cargo, gem: gem,
            composer: FailingComposer(), nuget: AbsentNuGet(), uv: uv, pnpm: pnpm, maven: maven,
            defaults: defaults
        )

        let results = await applier.apply(.chinaMainland)
        let v = MirrorPresetProfile.chinaMainland.values
        XCTAssertEqual(npm.written, v.npmRegistry)
        XCTAssertEqual(pip.written, v.pipIndex)
        XCTAssertEqual(cargo.written, v.cargoRegistry)
        XCTAssertEqual(gem.written, v.gemSource)
        XCTAssertEqual(uv.written, v.uvIndex)
        XCTAssertEqual(pnpm.written, v.pnpmRegistry)
        XCTAssertEqual(maven.settings.mirrors.first?.url, v.mavenMirror?.url)
        XCTAssertEqual(defaults.string(forKey: DownloadMirrors.nodeKey), v.nodeDownload)
        XCTAssertEqual(defaults.string(forKey: DownloadMirrors.goKey), v.goDownload)

        func status(_ eco: MirrorPresetResult.Ecosystem) -> MirrorPresetResult.Status? {
            results.first { $0.ecosystem == eco }?.status
        }
        XCTAssertEqual(status(.go), .skipped("go not on PATH"))
        XCTAssertEqual(status(.nuget), .skipped("dotnet not on PATH"))
        guard case .failed = status(.composer) else { return XCTFail("composer should fail") }
        XCTAssertNil(go.written)

        // Restoring official removes the EnvMatrix-added Maven mirror.
        let restored = await applier.apply(.official)
        XCTAssertTrue(maven.settings.mirrors.isEmpty)
        XCTAssertEqual(npm.written, MirrorPresetProfile.official.values.npmRegistry)
        XCTAssertTrue(restored.first { $0.ecosystem == .maven }?.isApplied ?? false)
    }
}
