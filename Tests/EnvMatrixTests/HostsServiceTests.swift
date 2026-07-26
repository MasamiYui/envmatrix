import XCTest
@testable import EnvMatrix

final class HostsServiceTests: XCTestCase {
    var tempRoot: URL!
    var systemHostsURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-hosts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        systemHostsURL = tempRoot.appendingPathComponent("etc-hosts")
        try "127.0.0.1 localhost\n".data(using: .utf8)!.write(to: systemHostsURL, options: .atomic)
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    final class MockWriter: HostsPrivilegedWriter {
        var lastSource: URL?
        var shouldFail: Bool = false
        func write(source: URL, to systemPath: String) throws {
            if shouldFail {
                throw HostsServiceError.authCancelled
            }
            lastSource = source
            let data = try Data(contentsOf: source)
            try data.write(to: URL(fileURLWithPath: systemPath), options: .atomic)
        }
    }

    private func makeService(writer: HostsPrivilegedWriter = MockWriter()) -> DefaultHostsService {
        DefaultHostsService(
            baseDirectory: tempRoot.appendingPathComponent("appsupport", isDirectory: true),
            systemHostsPath: systemHostsURL.path,
            writer: writer
        )
    }

    func testReadSystemHosts() throws {
        let svc = makeService()
        XCTAssertEqual(try svc.readSystemHosts(), "127.0.0.1 localhost\n")
    }

    func testProfileCRUD() throws {
        let svc = makeService()
        XCTAssertTrue(svc.listProfiles().isEmpty)

        let p = try svc.writeProfile(name: "dev", text: "1.2.3.4 dev.local\n")
        XCTAssertEqual(p.name, "dev")
        XCTAssertEqual(svc.listProfiles().count, 1)
        XCTAssertEqual(try svc.readProfile(p), "1.2.3.4 dev.local\n")

        let renamed = try svc.renameProfile(p, to: "staging")
        XCTAssertEqual(renamed.name, "staging")
        XCTAssertEqual(svc.listProfiles().count, 1)

        try svc.deleteProfile(renamed)
        XCTAssertTrue(svc.listProfiles().isEmpty)
    }

    func testDefaultProfileMeta() throws {
        let svc = makeService()
        let p = try svc.writeProfile(name: "prod", text: "")
        try svc.setDefaultProfile(p)
        XCTAssertEqual(svc.defaultProfileName(), "prod")
        let list = svc.listProfiles()
        XCTAssertTrue(list.first(where: { $0.name == "prod" })?.isDefault ?? false)
    }

    func testInvalidNameRejected() {
        let svc = makeService()
        XCTAssertThrowsError(try svc.writeProfile(name: "", text: ""))
        XCTAssertThrowsError(try svc.writeProfile(name: "bad/name", text: ""))
    }

    func testWriteSystemHostsUsesWriterAndCreatesBackup() throws {
        let writer = MockWriter()
        let svc = makeService(writer: writer)
        let backup = try svc.writeSystemHosts(text: "9.9.9.9 dns.local\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        let backupText = try String(contentsOf: backup, encoding: .utf8)
        XCTAssertEqual(backupText, "127.0.0.1 localhost\n")

        let newText = try String(contentsOf: systemHostsURL, encoding: .utf8)
        XCTAssertEqual(newText, "9.9.9.9 dns.local\n")
        XCTAssertNotNil(writer.lastSource)
    }

    func testWriteSystemHostsPropagatesAuthCancel() {
        let writer = MockWriter()
        writer.shouldFail = true
        let svc = makeService(writer: writer)
        XCTAssertThrowsError(try svc.writeSystemHosts(text: "x\n")) { error in
            guard case HostsServiceError.authCancelled = error else {
                return XCTFail("Expected authCancelled, got \(error)")
            }
        }
    }
}
