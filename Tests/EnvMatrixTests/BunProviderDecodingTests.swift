import XCTest
@testable import EnvMatrix

final class BunProviderDecodingTests: XCTestCase {
    func testDecodeStripsBunPrefix() throws {
        let json = """
        [
          {"tag_name": "bun-v1.0.20", "draft": false, "prerelease": false},
          {"tag_name": "bun-v1.0.19", "draft": false, "prerelease": false},
          {"tag_name": "bun-v1.0.19-canary", "draft": false, "prerelease": true}
        ]
        """
        let data = Data(json.utf8)
        let versions = try BunProvider.decode(data: data)
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions[0].version, "1.0.20")
        XCTAssertEqual(versions[1].version, "1.0.19")
        XCTAssertTrue(versions.allSatisfy { $0.kind == .bun })
    }

    func testDecodeSkipsUnrecognizedTagFormat() throws {
        let json = """
        [
          {"tag_name": "just-a-broken-tag", "draft": false, "prerelease": false}
        ]
        """
        let data = Data(json.utf8)
        let versions = try BunProvider.decode(data: data)
        XCTAssertEqual(versions.count, 0)
    }
}
