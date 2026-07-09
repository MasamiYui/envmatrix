import XCTest
@testable import EnvMatrix

final class SkillsServiceTests: XCTestCase {
    var tempRoot: URL!
    var searchDir: URL!
    var service: DefaultSkillsService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-skills-\(UUID().uuidString)", isDirectory: true)
        // Simulate ~/.claude/skills so source is derived as "claude".
        searchDir = tempRoot
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: searchDir, withIntermediateDirectories: true)
        service = DefaultSkillsService(searchPaths: [searchDir])
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    private func makeSkillDir(named name: String) throws -> URL {
        let dir = searchDir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testListReturnsThreeSkillsWithFlags() throws {
        _ = try makeSkillDir(named: "alpha")
        _ = try makeSkillDir(named: "beta")
        _ = try makeSkillDir(named: "gamma.disabled")

        let skills = try service.list()
        XCTAssertEqual(skills.count, 3)

        let alpha = skills.first { $0.name == "alpha" }
        let beta = skills.first { $0.name == "beta" }
        let gamma = skills.first { $0.name == "gamma" }

        XCTAssertNotNil(alpha)
        XCTAssertNotNil(beta)
        XCTAssertNotNil(gamma)

        XCTAssertEqual(alpha?.isEnabled, true)
        XCTAssertEqual(beta?.isEnabled, true)
        XCTAssertEqual(gamma?.isEnabled, false)

        XCTAssertEqual(alpha?.source, "claude")
    }

    func testDisableRenamesDir() throws {
        let original = try makeSkillDir(named: "alpha")
        let skills = try service.list()
        let alpha = try XCTUnwrap(skills.first { $0.name == "alpha" })
        let updated = try service.disable(alpha)

        XCTAssertFalse(updated.isEnabled)
        XCTAssertEqual(updated.path.lastPathComponent, "alpha.disabled")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: updated.path.path))
    }

    func testEnableStripsDisabledSuffix() throws {
        let original = try makeSkillDir(named: "gamma.disabled")
        let skills = try service.list()
        let gamma = try XCTUnwrap(skills.first { $0.name == "gamma" })
        XCTAssertFalse(gamma.isEnabled)

        let updated = try service.enable(gamma)
        XCTAssertTrue(updated.isEnabled)
        XCTAssertEqual(updated.path.lastPathComponent, "gamma")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: updated.path.path))
    }

    func testDeleteRemovesDir() throws {
        let dir = try makeSkillDir(named: "alpha")
        let skills = try service.list()
        let alpha = try XCTUnwrap(skills.first { $0.name == "alpha" })
        try service.delete(alpha)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testSkillsDirectoriesReturnsConfiguredPaths() {
        XCTAssertEqual(service.skillsDirectories(), [searchDir])
    }
}
