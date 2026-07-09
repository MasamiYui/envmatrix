import XCTest
@testable import EnvMatrix

final class CLIConfigServiceTests: XCTestCase {
    var tempRoot: URL!
    var settingsURL: URL!
    var service: DefaultCLIConfigService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-cliconfig-\(UUID().uuidString)", isDirectory: true)
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
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    func testListReturnsMaskedConfig() {
        let configs = service.list()
        XCTAssertEqual(configs.count, 1)
        let cfg = configs[0]
        XCTAssertEqual(cfg.id, "claude-code")
        XCTAssertEqual(cfg.model, "claude-3-5")
        XCTAssertEqual(cfg.apiBaseURL, "https://x")
        XCTAssertEqual(cfg.apiKeyMasked, "sk-a****1234")
    }

    func testSaveModelPreservesAPIKey() throws {
        let cfg = service.list()[0]
        try service.save(cfg, values: ["model": "claude-4"])

        let data = try Data(contentsOf: settingsURL)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["model"] as? String, "claude-4")
        XCTAssertEqual(json["apiKey"] as? String, "sk-abcdefghij1234")
    }

    func testSaveWithMaskedAPIKeyKeepsOriginal() throws {
        let cfg = service.list()[0]
        try service.save(cfg, values: ["apiKey": "****"])

        let data = try Data(contentsOf: settingsURL)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["apiKey"] as? String, "sk-abcdefghij1234")
    }

    func testSaveWithMaskedPatternKeepsOriginal() throws {
        let cfg = service.list()[0]
        try service.save(cfg, values: ["apiKey": "sk-a****1234"])

        let data = try Data(contentsOf: settingsURL)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["apiKey"] as? String, "sk-abcdefghij1234")
    }

    func testSaveWithNewAPIKeyUpdates() throws {
        let cfg = service.list()[0]
        try service.save(cfg, values: ["apiKey": "sk-newvalue"])

        let data = try Data(contentsOf: settingsURL)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["apiKey"] as? String, "sk-newvalue")
    }

    func testListSkipsMissingFiles() {
        let missing = tempRoot.appendingPathComponent("missing.json")
        let svc = DefaultCLIConfigService(configPaths: [
            CLIConfigPath(id: "trae-cn", name: "Trae CN", url: missing)
        ])
        XCTAssertTrue(svc.list().isEmpty)
    }
}
