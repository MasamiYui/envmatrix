import XCTest
@testable import EnvMatrix

final class ShellEnvServiceTests: XCTestCase {
    var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-shellenv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    private func writeFile(_ relative: String, _ contents: String) throws {
        let url = tempRoot.appendingPathComponent(relative)
        try contents.data(using: .utf8)!.write(to: url, options: .atomic)
    }

    func testAvailableFilesReturnsOnlyExisting() throws {
        try writeFile(".zshrc", "# zshrc\n")
        try writeFile(".zshenv", "# zshenv\n")

        let svc = DefaultShellEnvService(home: tempRoot, shellPath: "/bin/zsh")
        let kinds = svc.availableFiles().map { $0.kind }
        XCTAssertEqual(kinds, [.zshrc, .zshenv])
    }

    func testCurrentShellKindZsh() {
        let svc = DefaultShellEnvService(home: tempRoot, shellPath: "/bin/zsh")
        XCTAssertEqual(svc.currentShellKind(), .zshrc)
    }

    func testCurrentShellKindBash() {
        let svc = DefaultShellEnvService(home: tempRoot, shellPath: "/bin/bash")
        XCTAssertEqual(svc.currentShellKind(), .bashrc)
    }

    func testCurrentShellKindOther() {
        let svc = DefaultShellEnvService(home: tempRoot, shellPath: "/bin/dash")
        XCTAssertNil(svc.currentShellKind())
    }

    func testWriteBacksUpAndWrites() throws {
        try writeFile(".zshrc", "OLD\n")
        let svc = DefaultShellEnvService(home: tempRoot, shellPath: "/bin/zsh")
        let file = svc.availableFiles().first { $0.kind == .zshrc }!

        let backup = try svc.write(file, text: "NEW\n")
        let backupURL = try XCTUnwrap(backup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        let backupContents = try String(contentsOf: backupURL, encoding: .utf8)
        XCTAssertEqual(backupContents, "OLD\n")

        let finalContents = try String(contentsOf: file.url, encoding: .utf8)
        XCTAssertEqual(finalContents, "NEW\n")
    }

    func testWriteWithoutTargetReturnsNilBackup() throws {
        let svc = DefaultShellEnvService(home: tempRoot, shellPath: "/bin/zsh")
        let url = tempRoot.appendingPathComponent(".zshrc")
        let file = ShellRcFile(kind: .zshrc, url: url, exists: false, isCurrentShell: false)

        let backup = try svc.write(file, text: "FRESH\n")
        XCTAssertNil(backup)

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(contents, "FRESH\n")
    }

    func testAvailableFilesIsCurrentShell() throws {
        try writeFile(".zshrc", "# zshrc\n")
        let svc = DefaultShellEnvService(home: tempRoot, shellPath: "/bin/zsh")
        let first = try XCTUnwrap(svc.availableFiles().first)
        XCTAssertTrue(first.isCurrentShell)
    }

    func testReadReturnsExistingContents() throws {
        try writeFile(".zshrc", "HELLO\n")
        let svc = DefaultShellEnvService(home: tempRoot, shellPath: "/bin/zsh")
        let file = svc.availableFiles().first { $0.kind == .zshrc }!
        XCTAssertEqual(try svc.read(file), "HELLO\n")
    }

    func testReadMissingThrowsFileNotFound() {
        let svc = DefaultShellEnvService(home: tempRoot, shellPath: "/bin/zsh")
        let url = tempRoot.appendingPathComponent(".zshrc")
        let file = ShellRcFile(kind: .zshrc, url: url, exists: false, isCurrentShell: false)
        XCTAssertThrowsError(try svc.read(file)) { error in
            guard case ShellEnvServiceError.fileNotFound = error else {
                return XCTFail("Expected fileNotFound, got \(error)")
            }
        }
    }
}
