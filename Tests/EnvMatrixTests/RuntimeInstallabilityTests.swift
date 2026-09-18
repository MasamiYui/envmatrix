import XCTest
@testable import EnvMatrix

final class RuntimeInstallabilityTests: XCTestCase {
    func testDefaultsFollowDownloadURL() {
        let withURL = RuntimeVersion(kind: .node, version: "20.0.0", downloadURL: URL(string: "https://x/y.tar.gz"))
        let withoutURL = RuntimeVersion(kind: .dotnet, version: "8.0.100", downloadURL: nil)
        XCTAssertTrue(withURL.isInstallable)
        XCTAssertFalse(withoutURL.isInstallable)
    }

    func testExplicitOverrideWins() {
        let source = RuntimeVersion(kind: .ruby, version: "3.3.0",
                                    downloadURL: URL(string: "https://x/ruby-3.3.0.tar.gz"),
                                    isInstallable: false)
        XCTAssertFalse(source.isInstallable)
    }

    func testRubyAndPhpSourceTarballsAreNotInstallable() throws {
        let rubyIndex = "ruby-3.3.0.tar.gz\nruby-3.2.2.tar.gz\n"
        let ruby = try RubyProvider.decode(data: Data(rubyIndex.utf8))
        XCTAssertFalse(ruby.isEmpty)
        XCTAssertTrue(ruby.allSatisfy { !$0.isInstallable })

        let phpJSON = #"{"8.3":{"version":"8.3.1"},"8.2":{"version":"8.2.14"}}"#
        let php = try PhpProvider.decode(data: Data(phpJSON.utf8))
        XCTAssertFalse(php.isEmpty)
        XCTAssertTrue(php.allSatisfy { !$0.isInstallable })
    }

    func testInstallRejectsNonInstallableWithSuggestion() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-installability-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = DefaultRuntimeService(root: root, providers: [:], systemDetector: nil)
        let v = RuntimeVersion(kind: .rust, version: "1.80.0", downloadURL: nil)
        do {
            try await service.install(version: v) { _ in }
            XCTFail("expected notInstallable")
        } catch let err as RuntimeServiceError {
            guard case .notInstallable(let kind, let version, let suggestion) = err else {
                return XCTFail("unexpected error \(err)")
            }
            XCTAssertEqual(kind, .rust)
            XCTAssertEqual(version, "1.80.0")
            XCTAssertEqual(suggestion, "rustup toolchain install 1.80.0")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testManualInstallCommandsAreVersionAware() {
        XCTAssertEqual(RuntimeKind.php.manualInstallCommand(version: "8.3.1"), "brew install php@8.3")
        XCTAssertEqual(RuntimeKind.ruby.manualInstallCommand(version: "3.3.0"), "brew install ruby@3.3")
        XCTAssertEqual(RuntimeKind.erlang.manualInstallCommand(version: "26.2.1"), "brew install erlang@26")
        XCTAssertEqual(RuntimeKind.node.manualInstallCommand(version: "v20.11.0"), "brew install node@20")
        XCTAssertEqual(RuntimeKind.dotnet.manualInstallCommand(version: "8.0.100"), "brew install --cask dotnet-sdk@8")
    }
}
