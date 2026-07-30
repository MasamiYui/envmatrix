import XCTest
@testable import EnvMatrix

private final class PnpmStubShellPathResolver: ShellPathResolver {
    let dirs: [URL]
    init(dirs: [URL]) { self.dirs = dirs }
    func resolvePathDirs() -> [URL] { dirs }
}

final class PnpmServiceTests: XCTestCase {
    var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-pnpm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    // MARK: - parseGlobalPackages

    func testParseGlobalPackages_objectRoot() throws {
        let json = """
        {"dependencies":{"typescript":{"version":"5.4.5","path":"/x"},"pnpm":{"version":"9.0.0"},"eslint":{"version":"8.0.0"}}}
        """
        let packages = try DefaultPnpmService.parseGlobalPackages(json: json)
        XCTAssertEqual(packages.count, 3)
        XCTAssertEqual(packages.map { $0.name }, ["eslint", "pnpm", "typescript"])
        XCTAssertEqual(packages[2].version, "5.4.5")
        XCTAssertEqual(packages[2].path, "/x")
        XCTAssertNil(packages[1].path)
    }

    func testParseGlobalPackages_arrayRoot() throws {
        let json = """
        [{"dependencies":{"typescript":{"version":"5.4.5","path":"/x"},"pnpm":{"version":"9.0.0"},"eslint":{"version":"8.0.0"}}}]
        """
        let packages = try DefaultPnpmService.parseGlobalPackages(json: json)
        XCTAssertEqual(packages.count, 3)
        XCTAssertEqual(packages.map { $0.name }, ["eslint", "pnpm", "typescript"])
    }

    func testParseGlobalPackages_emptyDependencies() throws {
        let json = "{\"dependencies\":{}}"
        let packages = try DefaultPnpmService.parseGlobalPackages(json: json)
        XCTAssertEqual(packages.count, 0)
    }

    // MARK: - parseStorePath

    func testParseStorePath_trimsWhitespace() {
        let raw = "/Users/x/.local/share/pnpm/store/v3\n\t "
        let parsed = DefaultPnpmService.parseStorePath(raw)
        XCTAssertEqual(parsed, "/Users/x/.local/share/pnpm/store/v3")
    }

    // MARK: - setRegistry with existing file

    func testSetRegistry_createsTimestampedBackupAndReadsBack() throws {
        let npmrcURL = tempRoot.appendingPathComponent(".npmrc")
        let initial = "registry=https://registry.npmjs.org/\n"
        try initial.write(to: npmrcURL, atomically: true, encoding: .utf8)

        let service = DefaultPnpmConfigService(npmrcURL: npmrcURL)
        let newURL = "https://registry.npmmirror.com"
        try service.setRegistry(url: newURL)

        // (a) backup file matches pattern .npmrc.<yyyyMMdd-HHmmss>.pnpm.bak
        let entries = try FileManager.default.contentsOfDirectory(atPath: tempRoot.path)
        let pattern = "^\\.npmrc\\.\\d{8}-\\d{6}\\.pnpm\\.bak$"
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = entries.filter { name in
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            return regex.firstMatch(in: name, options: [], range: range) != nil
        }
        XCTAssertFalse(matches.isEmpty, "Expected a timestamped .pnpm.bak backup, got: \(entries)")

        // (b) currentRegistry should now report the new URL
        let current = try service.currentRegistry()
        XCTAssertEqual(current, newURL)
    }

    // MARK: - isAvailable (skip if system has no pnpm)

    func testIsAvailableSkippedIfSystemLacksPnpm() async throws {
        let service = DefaultPnpmService()
        let available = await service.isAvailable()
        if !available {
            throw XCTSkip("Host machine has no `pnpm` on PATH or in fallback paths; skipping.")
        }
        XCTAssertTrue(available)
    }
}
