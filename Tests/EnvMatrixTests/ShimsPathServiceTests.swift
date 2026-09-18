import XCTest
@testable import EnvMatrix

final class ShimsPathServiceTests: XCTestCase {
    private struct StubResolver: ShellPathResolver {
        let dirs: [URL]
        func resolvePathDirs() -> [URL] { dirs }
    }

    private var tmpHome: URL!
    private var shims: URL!

    override func setUpWithError() throws {
        tmpHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-shims-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpHome, withIntermediateDirectories: true)
        shims = tmpHome.appendingPathComponent(".envmatrix/shims", isDirectory: true)
        try FileManager.default.createDirectory(at: shims, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpHome)
    }

    private func makeService(pathDirs: [URL]) -> DefaultShimsPathService {
        DefaultShimsPathService(
            shimsDir: shims,
            pathResolver: StubResolver(dirs: pathDirs),
            shellEnv: DefaultShellEnvService(home: tmpHome, shellPath: "/bin/zsh"),
            home: tmpHome
        )
    }

    func testDetectsShimsOnPath() {
        XCTAssertTrue(makeService(pathDirs: [URL(fileURLWithPath: "/usr/bin"), shims]).isShimsOnPath())
        XCTAssertFalse(makeService(pathDirs: [URL(fileURLWithPath: "/usr/bin")]).isShimsOnPath())
    }

    func testExportLineUsesHomeVariable() {
        let svc = makeService(pathDirs: [])
        XCTAssertEqual(svc.exportLine, "export PATH=\"$HOME/.envmatrix/shims:$PATH\"")
    }

    func testAddToShellRcCreatesFileAndIsIdempotent() throws {
        let svc = makeService(pathDirs: [])
        let file = try svc.addShimsToShellRc()
        XCTAssertEqual(file.kind, .zshrc)
        let first = try String(contentsOf: file.url, encoding: .utf8)
        XCTAssertTrue(first.contains(DefaultShimsPathService.marker))
        XCTAssertTrue(first.contains(svc.exportLine))

        try svc.addShimsToShellRc()
        let second = try String(contentsOf: file.url, encoding: .utf8)
        XCTAssertEqual(first, second, "second write must not duplicate the export")
    }

    func testAddToShellRcAppendsToExistingContent() throws {
        let rc = tmpHome.appendingPathComponent(".zshrc")
        try "alias ll='ls -la'".write(to: rc, atomically: true, encoding: .utf8)
        let svc = makeService(pathDirs: [])
        try svc.addShimsToShellRc()
        let text = try String(contentsOf: rc, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("alias ll='ls -la'\n"))
        XCTAssertTrue(text.hasSuffix(svc.exportLine + "\n"))
        // A backup must exist next to the rc file.
        let siblings = try FileManager.default.contentsOfDirectory(atPath: tmpHome.path)
        XCTAssertTrue(siblings.contains { $0.contains(".zshrc.envmatrix.") && $0.hasSuffix(".bak") })
    }

    func testRecognisesHandWrittenExport() throws {
        let rc = tmpHome.appendingPathComponent(".zshrc")
        try "export PATH=\"$HOME/.envmatrix/shims:$PATH\"\n".write(to: rc, atomically: true, encoding: .utf8)
        let svc = makeService(pathDirs: [])
        try svc.addShimsToShellRc()
        let text = try String(contentsOf: rc, encoding: .utf8)
        XCTAssertFalse(text.contains(DefaultShimsPathService.marker))
    }
}
