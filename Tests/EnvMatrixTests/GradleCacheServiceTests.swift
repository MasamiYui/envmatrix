import XCTest
@testable import EnvMatrix

final class GradleCacheServiceTests: XCTestCase {

    private var tempHome: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = fm.temporaryDirectory
            .appendingPathComponent("GradleCacheServiceTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        tempHome = base
    }

    override func tearDownWithError() throws {
        if let tempHome = tempHome, fm.fileExists(atPath: tempHome.path) {
            try? fm.removeItem(at: tempHome)
        }
        tempHome = nil
        try super.tearDownWithError()
    }

    func testScanArtifactsFromFakeHome() throws {
        let versionDir = tempHome
            .appendingPathComponent("caches", isDirectory: true)
            .appendingPathComponent("modules-2", isDirectory: true)
            .appendingPathComponent("files-2.1", isDirectory: true)
            .appendingPathComponent("org.slf4j", isDirectory: true)
            .appendingPathComponent("slf4j-api", isDirectory: true)
            .appendingPathComponent("2.0.0", isDirectory: true)
            .appendingPathComponent("hash", isDirectory: true)
        try fm.createDirectory(at: versionDir, withIntermediateDirectories: true)

        let jarURL = versionDir.appendingPathComponent("slf4j-api-2.0.0.jar")
        let payload = Data(repeating: 0x41, count: 128)
        try payload.write(to: jarURL)

        let artifacts = GradleCacheService.scanArtifacts(home: tempHome)
        XCTAssertEqual(artifacts.count, 1)
        let a = try XCTUnwrap(artifacts.first)
        XCTAssertEqual(a.group, "org.slf4j")
        XCTAssertEqual(a.artifact, "slf4j-api")
        XCTAssertEqual(a.version, "2.0.0")
        XCTAssertEqual(a.id, "org.slf4j:slf4j-api:2.0.0")
        XCTAssertGreaterThanOrEqual(a.sizeBytes, 128)
    }

    func testScanWrapperDists() throws {
        let binDir = tempHome
            .appendingPathComponent("wrapper", isDirectory: true)
            .appendingPathComponent("dists", isDirectory: true)
            .appendingPathComponent("gradle-8.5-all", isDirectory: true)
            .appendingPathComponent("hash", isDirectory: true)
            .appendingPathComponent("gradle-8.5", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)

        let gradleBin = binDir.appendingPathComponent("gradle")
        let payload = Data(repeating: 0x42, count: 10)
        try payload.write(to: gradleBin)

        let dists = GradleCacheService.scanWrapperDists(home: tempHome)
        XCTAssertEqual(dists.count, 1)
        let d = try XCTUnwrap(dists.first)
        XCTAssertEqual(d.versionLabel, "gradle-8.5-all")
        XCTAssertEqual(d.id, "gradle-8.5-all")
        XCTAssertGreaterThanOrEqual(d.sizeBytes, 10)
    }

    func testEmptyGradleHome() {
        let artifacts = GradleCacheService.scanArtifacts(home: tempHome)
        XCTAssertTrue(artifacts.isEmpty)

        let dists = GradleCacheService.scanWrapperDists(home: tempHome)
        XCTAssertTrue(dists.isEmpty)
    }
}
