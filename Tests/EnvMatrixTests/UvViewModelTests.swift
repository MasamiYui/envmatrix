import XCTest
@testable import EnvMatrix

// MARK: - Mock services

private final class MockUvService: UvService {
    var availableResult: Bool
    var tools: [UvTool]
    var cacheResult: UvCacheStats
    var listError: Error?
    var uninstalled: [String] = []
    var cleanCount: Int = 0

    init(available: Bool = true,
         tools: [UvTool] = [],
         cache: UvCacheStats = UvCacheStats(path: "/tmp/uv-cache", sizeBytes: 0),
         listError: Error? = nil) {
        self.availableResult = available
        self.tools = tools
        self.cacheResult = cache
        self.listError = listError
    }

    func isAvailable() async -> Bool { availableResult }

    func listGlobalTools() async throws -> [UvTool] {
        if let err = listError { throw err }
        return tools
    }

    func uninstallTool(name: String) async throws {
        uninstalled.append(name)
        tools.removeAll { $0.name == name }
    }

    func cacheStats() async throws -> UvCacheStats { cacheResult }

    func cacheClean() async throws {
        cleanCount += 1
        cacheResult = UvCacheStats(path: cacheResult.path, sizeBytes: 0)
    }
}

private final class MockUvConfigService: UvConfigService {
    let uvConfigURL: URL
    var currentValue: String
    var presets: [UvRegistryPreset]
    var savedURLs: [String] = []

    init(current: String = "https://pypi.org/simple",
         presets: [UvRegistryPreset] = [],
         url: URL = URL(fileURLWithPath: "/tmp/uv.toml")) {
        self.currentValue = current
        self.presets = presets
        self.uvConfigURL = url
    }

    func currentRegistry() throws -> String { currentValue }

    func setRegistry(url: String) throws {
        savedURLs.append(url)
        currentValue = url
    }

    func presetRegistries() -> [UvRegistryPreset] { presets }
}

@MainActor
final class UvViewModelTests: XCTestCase {

    // MARK: - UvGlobalToolsViewModel

    func testGlobalToolsLoadPopulatesThree() async {
        let mock = MockUvService(
            available: true,
            tools: [
                UvTool(name: "ruff", version: "0.4.0"),
                UvTool(name: "black", version: "24.3.0"),
                UvTool(name: "mypy", version: "1.10.0")
            ]
        )
        let vm = UvGlobalToolsViewModel(service: mock)
        await vm.load()
        XCTAssertTrue(vm.uvAvailable)
        XCTAssertEqual(vm.tools.count, 3)
        XCTAssertEqual(vm.filtered.count, 3)
        XCTAssertNil(vm.errorMessage)
    }

    func testGlobalToolsUnavailableProducesEmptyState() async {
        let mock = MockUvService(available: false, tools: [
            UvTool(name: "ruff", version: "0.4.0")
        ])
        let vm = UvGlobalToolsViewModel(service: mock)
        await vm.load()
        XCTAssertFalse(vm.uvAvailable)
        XCTAssertTrue(vm.tools.isEmpty)
        XCTAssertTrue(vm.filtered.isEmpty)
    }

    func testGlobalToolsSearchFilter() async {
        let mock = MockUvService(
            available: true,
            tools: [
                UvTool(name: "ruff", version: "0.4.0"),
                UvTool(name: "black", version: "24.3.0"),
                UvTool(name: "mypy", version: "1.10.0")
            ]
        )
        let vm = UvGlobalToolsViewModel(service: mock)
        await vm.load()
        vm.updateSearch("ru")
        XCTAssertEqual(vm.filtered.count, 1)
        XCTAssertEqual(vm.filtered.first?.name, "ruff")
    }

    // MARK: - UvCacheViewModel

    func testCacheLoadUnavailable() async {
        let mock = MockUvService(available: false)
        let vm = UvCacheViewModel(service: mock)
        await vm.load()
        XCTAssertFalse(vm.uvAvailable)
        XCTAssertNil(vm.stats)
    }

    func testCacheLoadPopulatesStats() async {
        let stats = UvCacheStats(path: "/tmp/uv-cache", sizeBytes: 1234)
        let mock = MockUvService(available: true, cache: stats)
        let vm = UvCacheViewModel(service: mock)
        await vm.load()
        XCTAssertTrue(vm.uvAvailable)
        XCTAssertEqual(vm.stats?.path, "/tmp/uv-cache")
        XCTAssertEqual(vm.stats?.sizeBytes, 1234)
    }

    // MARK: - UvRegistryViewModel

    func testRegistryLoadUnavailableStillLoadsPresets() async {
        let presets = [
            UvRegistryPreset(id: "pypi", name: "PyPI", url: "https://pypi.org/simple")
        ]
        let uv = MockUvService(available: false)
        let cfg = MockUvConfigService(current: "https://pypi.org/simple", presets: presets)
        let vm = UvRegistryViewModel(configService: cfg, uvService: uv)
        await vm.load()
        XCTAssertFalse(vm.uvAvailable)
        XCTAssertEqual(vm.presets.count, 1)
        XCTAssertEqual(vm.currentRegistry, "https://pypi.org/simple")
    }

    func testRegistryApplyCustomInvalidURLSetsError() async {
        let uv = MockUvService(available: true)
        let cfg = MockUvConfigService()
        let vm = UvRegistryViewModel(configService: cfg, uvService: uv)
        await vm.load()
        vm.customURL = "ftp://not-supported"
        await vm.applyCustomURL()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(cfg.savedURLs.isEmpty)
    }
}
