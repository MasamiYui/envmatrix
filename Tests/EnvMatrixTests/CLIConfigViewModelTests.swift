import XCTest
@testable import EnvMatrix

@MainActor
final class CLIConfigViewModelTests: XCTestCase {
    var tempRoot: URL!
    var settingsURL: URL!
    var service: DefaultCLIConfigService!
    var vm: CLIConfigViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-cliconfig-vm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        settingsURL = tempRoot.appendingPathComponent("settings.json")
        let seed: [String: Any] = [
            "model": "claude-3-5",
            "apiBaseURL": "https://x",
            "apiKey": "sk-abcdefghij1234"
        ]
        let data = try JSONSerialization.data(withJSONObject: seed, options: [.prettyPrinted])
        try data.write(to: settingsURL, options: .atomic)

        service = DefaultCLIConfigService(configPaths: [
            CLIConfigPath(id: "claude-code", name: "Claude Code", url: settingsURL)
        ])
        vm = CLIConfigViewModel(service: service)
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    func testRefreshLoadsMaskedConfig() throws {
        vm.refresh()
        XCTAssertEqual(vm.configs.count, 1)
        let cfg = try XCTUnwrap(vm.configs.first)
        XCTAssertEqual(cfg.id, "claude-code")
        XCTAssertTrue(cfg.apiKeyMasked?.contains("****") ?? false)
    }

    func testSelectLoadsMaskedAPIKey() throws {
        vm.refresh()
        let cfg = try XCTUnwrap(vm.configs.first)
        vm.select(cfg)
        XCTAssertEqual(vm.model, "claude-3-5")
        XCTAssertEqual(vm.apiBaseURL, "https://x")
        XCTAssertTrue(vm.apiKey.contains("****"))
    }

    func testSavePreservesAPIKeyWhenMasked() throws {
        vm.refresh()
        let cfg = try XCTUnwrap(vm.configs.first)
        vm.select(cfg)

        vm.model = "new"
        vm.save()

        let data = try Data(contentsOf: settingsURL)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["model"] as? String, "new")
        XCTAssertEqual(json["apiKey"] as? String, "sk-abcdefghij1234")
    }

    func testSaveWithNewAPIKeyUpdatesFile() throws {
        vm.refresh()
        let cfg = try XCTUnwrap(vm.configs.first)
        vm.select(cfg)

        vm.apiKey = "sk-brandnew"
        vm.save()

        let data = try Data(contentsOf: settingsURL)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["apiKey"] as? String, "sk-brandnew")
    }
}
