import XCTest
@testable import EnvMatrix

private final class UvStubShellPathResolver: ShellPathResolver {
    let dirs: [URL]
    init(dirs: [URL]) { self.dirs = dirs }
    func resolvePathDirs() -> [URL] { dirs }
}

final class UvServiceTests: XCTestCase {
    var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-uv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    // MARK: - parseToolList

    func testParseToolListReturnsThree() {
        let fixture = "ruff v0.4.0\n    - ruff\nblack v24.3.0\nmypy v1.10.0\n    - mypy\n    - stubgen"
        let tools = DefaultUvService.parseToolList(stdout: fixture)
        XCTAssertEqual(tools.count, 3)
        XCTAssertEqual(tools[0].name, "ruff")
        XCTAssertEqual(tools[0].version, "0.4.0")
        XCTAssertEqual(tools[1].name, "black")
        XCTAssertEqual(tools[1].version, "24.3.0")
        XCTAssertEqual(tools[2].name, "mypy")
        XCTAssertEqual(tools[2].version, "1.10.0")
    }

    // MARK: - setRegistry with existing file

    func testSetRegistryCreatesBackup() throws {
        let configURL = tempRoot.appendingPathComponent("uv.toml")
        let initial = """
        [[index]]
        url = "https://pypi.org/simple"
        """
        try initial.write(to: configURL, atomically: true, encoding: .utf8)

        let service = DefaultUvConfigService(uvConfigURL: configURL)
        let newURL = "https://pypi.tuna.tsinghua.edu.cn/simple"
        try service.setRegistry(url: newURL)

        // (a) A backup file exists in the same directory matching uv.toml.*.bak
        let entries = try FileManager.default.contentsOfDirectory(atPath: tempRoot.path)
        let backups = entries.filter { $0.hasPrefix("uv.toml.") && $0.hasSuffix(".bak") }
        XCTAssertFalse(backups.isEmpty, "Expected at least one backup file with pattern uv.toml.*.bak")

        // (b) currentRegistry should now report the new URL
        let current = try service.currentRegistry()
        XCTAssertEqual(current, newURL)
    }

    // MARK: - setRegistry when file missing

    func testSetRegistryWhenNoFile() throws {
        let configURL = tempRoot.appendingPathComponent("uv.toml")
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))

        let service = DefaultUvConfigService(uvConfigURL: configURL)
        let newURL = "https://mirrors.aliyun.com/pypi/simple/"
        try service.setRegistry(url: newURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        let current = try service.currentRegistry()
        XCTAssertEqual(current, newURL)
    }

    // MARK: - isAvailable false when binary missing

    func testIsAvailableFalseWhenBinaryMissing() async throws {
        // Inject an empty PATH via a stub resolver.
        // NOTE: DefaultUvService also probes hardcoded fallbacks such as
        // /usr/local/bin, /opt/homebrew/bin, ~/.local/bin and ~/.cargo/bin.
        // If the local machine has `uv` installed in any of those, this test
        // cannot deterministically assert `false` without deeper mocking.
        // We therefore skip when a real uv binary is discoverable in fallbacks.
        // TODO: Consider making fallback paths injectable to enable a fully
        // deterministic test without touching the host filesystem.
        let fm = FileManager.default
        let fallbackPaths = [
            "/usr/local/bin/uv",
            "/opt/homebrew/bin/uv",
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/uv"),
            (NSHomeDirectory() as NSString).appendingPathComponent(".cargo/bin/uv")
        ]
        let hostHasUv = fallbackPaths.contains { fm.isExecutableFile(atPath: $0) }
        if hostHasUv {
            throw XCTSkip("Host machine has a real `uv` in a fallback path; skipping negative test.")
        }
        let service = DefaultUvService(
            shellPathResolver: UvStubShellPathResolver(dirs: [])
        )
        let available = await service.isAvailable()
        XCTAssertFalse(available)
    }
}
