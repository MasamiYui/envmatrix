import XCTest
@testable import EnvMatrix

@MainActor
final class SkillsViewModelTests: XCTestCase {
    var tempRoot: URL!
    var searchDir: URL!
    var service: DefaultSkillsService!
    var vm: SkillsViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-skills-vm-\(UUID().uuidString)", isDirectory: true)
        searchDir = tempRoot
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: searchDir, withIntermediateDirectories: true)
        service = DefaultSkillsService(searchPaths: [searchDir])
        vm = SkillsViewModel(service: service)
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    private func makeSkillDir(_ name: String) throws -> URL {
        let dir = searchDir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testRefreshLoadsSkills() throws {
        _ = try makeSkillDir("alpha")
        _ = try makeSkillDir("beta.disabled")

        vm.refresh()

        XCTAssertEqual(vm.skills.count, 2)
        XCTAssertTrue(vm.skills.contains(where: { $0.name == "alpha" && $0.isEnabled }))
        XCTAssertTrue(vm.skills.contains(where: { $0.name == "beta" && !$0.isEnabled }))
    }

    func testToggleDisablesEnabledSkill() throws {
        let dir = try makeSkillDir("alpha")
        vm.refresh()
        let alpha = try XCTUnwrap(vm.skills.first(where: { $0.name == "alpha" }))

        vm.toggle(alpha)

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        let disabled = searchDir.appendingPathComponent("alpha.disabled")
        XCTAssertTrue(FileManager.default.fileExists(atPath: disabled.path))
        let refreshed = try XCTUnwrap(vm.skills.first(where: { $0.name == "alpha" }))
        XCTAssertFalse(refreshed.isEnabled)
    }

    func testToggleEnablesDisabledSkill() throws {
        let dir = try makeSkillDir("gamma.disabled")
        vm.refresh()
        let gamma = try XCTUnwrap(vm.skills.first(where: { $0.name == "gamma" }))
        XCTAssertFalse(gamma.isEnabled)

        vm.toggle(gamma)

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        let enabled = searchDir.appendingPathComponent("gamma")
        XCTAssertTrue(FileManager.default.fileExists(atPath: enabled.path))
        let refreshed = try XCTUnwrap(vm.skills.first(where: { $0.name == "gamma" }))
        XCTAssertTrue(refreshed.isEnabled)
    }

    func testDeleteRemovesSkill() throws {
        let dir = try makeSkillDir("alpha")
        vm.refresh()
        let alpha = try XCTUnwrap(vm.skills.first(where: { $0.name == "alpha" }))

        vm.delete(alpha)

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertTrue(vm.skills.isEmpty)
    }
}
