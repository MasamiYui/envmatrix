import XCTest
@testable import EnvMatrix

final class RuntimeServiceTests: XCTestCase {
    var tempRoot: URL!
    var service: DefaultRuntimeService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        tempRoot = base
        service = DefaultRuntimeService(root: tempRoot, providers: [:], systemDetector: nil)
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    private func createFakeNode(version: String) throws -> URL {
        let versionDir = tempRoot
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("node", isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
        let binDir = versionDir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let nodeBin = binDir.appendingPathComponent("node")
        FileManager.default.createFile(atPath: nodeBin.path, contents: Data("#!/bin/sh\n".utf8))
        return versionDir
    }

    func testListInstalledReturnsOneEntry() throws {
        _ = try createFakeNode(version: "18.0.0")
        let installed = try service.listInstalled(kind: .node)
        XCTAssertEqual(installed.count, 1)
        XCTAssertEqual(installed.first?.version, "18.0.0")
        XCTAssertEqual(installed.first?.kind, .node)
    }

    func testActivateCreatesSymlink() throws {
        _ = try createFakeNode(version: "18.0.0")
        let rv = RuntimeVersion(kind: .node, version: "18.0.0")
        try service.activate(version: rv)

        let shim = tempRoot
            .appendingPathComponent("shims", isDirectory: true)
            .appendingPathComponent("node")
        let attrs = try FileManager.default.attributesOfItem(atPath: shim.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)

        let dest = try FileManager.default.destinationOfSymbolicLink(atPath: shim.path)
        XCTAssertTrue(dest.contains("versions/node/18.0.0/bin/node"),
                      "symlink destination should point to version bin, got: \(dest)")

        XCTAssertEqual(service.currentActive(kind: .node), "18.0.0")
    }

    func testUninstallRemovesDirAndShim() throws {
        _ = try createFakeNode(version: "18.0.0")
        let rv = RuntimeVersion(kind: .node, version: "18.0.0")
        try service.activate(version: rv)
        try service.uninstall(version: rv)

        let versionDir = tempRoot
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("node", isDirectory: true)
            .appendingPathComponent("18.0.0", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: versionDir.path))

        let shim = tempRoot
            .appendingPathComponent("shims", isDirectory: true)
            .appendingPathComponent("node")
        // shim should either not exist, or not be a symlink pointing to removed dir
        let attrs = try? FileManager.default.attributesOfItem(atPath: shim.path)
        if attrs != nil {
            XCTFail("shim should have been removed since it pointed to uninstalled version")
        }
    }

    func testUninstallMissingThrows() {
        let rv = RuntimeVersion(kind: .node, version: "99.99.99")
        XCTAssertThrowsError(try service.uninstall(version: rv))
    }
}
