import XCTest
@testable import EnvMatrix

final class UpdateCheckTests: XCTestCase {
    func testSemanticVersionComparison() {
        XCTAssertTrue(SemanticVersion.isNewer("0.4.0", than: "0.3.9"))
        XCTAssertTrue(SemanticVersion.isNewer("v1.0.0", than: "0.9.99"))
        XCTAssertTrue(SemanticVersion.isNewer("1.2", than: "1.1.9"))
        XCTAssertFalse(SemanticVersion.isNewer("1.2.0", than: "1.2"))
        XCTAssertFalse(SemanticVersion.isNewer("0.3.0", than: "0.3.0"))
        XCTAssertTrue(SemanticVersion.isNewer("1.0.0", than: "1.0.0-beta.1"))
        XCTAssertFalse(SemanticVersion.isNewer("1.0.0-beta.1", than: "1.0.0"))
    }

    func testDecodeStripsTagPrefix() throws {
        let json = #"{"tag_name":"v0.5.2","html_url":"https://github.com/MasamiYui/envmatrix/releases/tag/v0.5.2","body":"notes"}"#
        let release = try GitHubUpdateCheckService.decode(Data(json.utf8))
        XCTAssertEqual(release.version, "0.5.2")
        XCTAssertEqual(release.tag, "v0.5.2")
        XCTAssertEqual(release.notes, "notes")
    }

    private struct StubService: UpdateCheckService {
        let release: AppRelease
        func fetchLatestRelease() async throws -> AppRelease { release }
    }

    private func makeDefaults() -> UserDefaults {
        let name = "envmatrix-update-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @MainActor
    func testCheckerReportsAvailableAndHonoursSkip() async {
        let release = AppRelease(version: "0.9.0", tag: "v0.9.0",
                                 url: URL(string: "https://example.com")!, notes: nil)
        let checker = UpdateChecker(service: StubService(release: release),
                                    defaults: makeDefaults(),
                                    currentVersion: { "0.8.0" })
        await checker.check()
        XCTAssertEqual(checker.state, .available(release))
        XCTAssertEqual(checker.pendingRelease, release)

        checker.skip(release)
        XCTAssertNil(checker.pendingRelease)
        checker.clearSkipped()
        XCTAssertEqual(checker.pendingRelease, release)
    }

    @MainActor
    func testCheckerReportsUpToDate() async {
        let release = AppRelease(version: "0.8.0", tag: "v0.8.0",
                                 url: URL(string: "https://example.com")!, notes: nil)
        let checker = UpdateChecker(service: StubService(release: release),
                                    defaults: makeDefaults(),
                                    currentVersion: { "0.8.0" })
        await checker.check()
        XCTAssertEqual(checker.state, .upToDate(latest: "0.8.0"))
        XCTAssertNil(checker.pendingRelease)
    }

    func testDevBuildsAreNotRealVersions() {
        XCTAssertFalse(UpdateChecker.isRealVersion("dev"))
        XCTAssertTrue(UpdateChecker.isRealVersion("0.3.0"))
    }
}
