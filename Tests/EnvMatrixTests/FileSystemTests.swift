import XCTest
@testable import EnvMatrix

final class FileSystemTests: XCTestCase {
    func testHomeURLNonEmpty() {
        XCTAssertFalse(FileSystem.homeURL.path.isEmpty)
    }

    func testEnvmatrixRootSuffix() {
        XCTAssertTrue(
            FileSystem.envmatrixRoot.path.hasSuffix("/.envmatrix"),
            "envmatrixRoot should end with /.envmatrix but was \(FileSystem.envmatrixRoot.path)"
        )
    }

    func testVersionDirPath() {
        let url = FileSystem.versionDir(kind: .node, version: "20.0.0")
        XCTAssertTrue(url.path.hasSuffix("/.envmatrix/versions/node/20.0.0"))
    }
}
