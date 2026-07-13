import XCTest
@testable import EnvMatrix

final class SystemRuntimeDetectorTests: XCTestCase {
    private var detector: DefaultSystemRuntimeDetector!

    override func setUp() {
        super.setUp()
        detector = DefaultSystemRuntimeDetector()
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    // MARK: - parseVersion

    func testParseNodeVersion() {
        XCTAssertEqual(detector.parseVersion("v20.10.0\n", kind: .node), "20.10.0")
    }

    func testParsePythonVersion() {
        XCTAssertEqual(detector.parseVersion("Python 3.11.7\n", kind: .python), "3.11.7")
    }

    func testParseJavaVersion() {
        XCTAssertEqual(
            detector.parseVersion(
                "openjdk version \"17.0.9\" 2023-10-17\n",
                kind: .java
            ),
            "17.0.9"
        )
        XCTAssertEqual(
            detector.parseVersion("java version \"21\"\n", kind: .java),
            "21"
        )
    }

    func testParseGoVersion() {
        XCTAssertEqual(
            detector.parseVersion("go version go1.22.1 darwin/arm64\n", kind: .go),
            "1.22.1"
        )
    }

    func testParseRustVersion() {
        XCTAssertEqual(
            detector.parseVersion("rustc 1.75.0 (82e1608df 2023-12-21)\n", kind: .rust),
            "1.75.0"
        )
    }

    func testParseRubyVersion() {
        XCTAssertEqual(
            detector.parseVersion(
                "ruby 3.3.0p0 (2023-12-25 revision xxx) [arm64-darwin23]\n",
                kind: .ruby
            ),
            "3.3.0"
        )
    }

    func testParsePhpVersion() {
        XCTAssertEqual(
            detector.parseVersion("PHP 8.3.0 (cli) (built: Jan 01 2024)\n", kind: .php),
            "8.3.0"
        )
    }

    func testParseDenoVersion() {
        XCTAssertEqual(
            detector.parseVersion(
                "deno 1.40.0 (release, aarch64-apple-darwin)\n",
                kind: .deno
            ),
            "1.40.0"
        )
    }

    func testParseBunVersion() {
        XCTAssertEqual(detector.parseVersion("1.0.20\n", kind: .bun), "1.0.20")
    }

    func testParseDotnetVersion() {
        XCTAssertEqual(detector.parseVersion("8.0.100\n", kind: .dotnet), "8.0.100")
    }

    func testParseErlangVersion() {
        XCTAssertEqual(
            detector.parseVersion(
                "Erlang (SMP,ASYNC_THREADS) (BEAM) emulator version 14.2.1\n",
                kind: .erlang
            ),
            "14.2.1"
        )
    }

    func testParseEmptyReturnsNil() {
        XCTAssertNil(detector.parseVersion("\n", kind: .node))
    }

    // MARK: - RuntimeVersion id for system entries

    func testSystemRuntimeVersionIDHasSystemPrefix() {
        let v = RuntimeVersion(kind: .node, version: "20.10.0", isSystem: true)
        XCTAssertTrue(
            v.id.hasPrefix("node-system-"),
            "System entry id should be prefixed with node-system-, got: \(v.id)"
        )
        XCTAssertEqual(v.id, "node-system-20.10.0")
    }

    func testManagedRuntimeVersionIDUnchanged() {
        let v = RuntimeVersion(kind: .node, version: "20.10.0")
        XCTAssertEqual(v.id, "node-20.10.0")
        XCTAssertFalse(v.isSystem)
    }

    // MARK: - expandGlob (minimal sanity)

    func testExpandGlobEnumeratesOneLevel() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-glob-\(UUID().uuidString)", isDirectory: true)
        let subA = tempRoot.appendingPathComponent("a/bin", isDirectory: true)
        let subB = tempRoot.appendingPathComponent("b/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: subA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subB, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let matches = detector.expandGlob("\(tempRoot.path)/*/bin")
        // Compare using resolved/standardized paths to avoid /var vs /private/var mismatch.
        let resolved = Set(matches.map { $0.resolvingSymlinksInPath().path })
        let expectA = subA.resolvingSymlinksInPath().path
        let expectB = subB.resolvingSymlinksInPath().path
        XCTAssertTrue(resolved.contains(expectA), "expected \(expectA) in \(resolved)")
        XCTAssertTrue(resolved.contains(expectB), "expected \(expectB) in \(resolved)")
    }
}
