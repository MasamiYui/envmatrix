import XCTest
@testable import EnvMatrix

final class DenoProviderDecodingTests: XCTestCase {
    func testDecodeStripsVPrefix() throws {
        let json = """
        [
          {"tag_name": "v1.40.0", "draft": false, "prerelease": false},
          {"tag_name": "v1.39.4", "draft": false, "prerelease": false},
          {"tag_name": "v1.39.3-rc.1", "draft": false, "prerelease": true}
        ]
        """
        let data = Data(json.utf8)
        let versions = try DenoProvider.decode(data: data)
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions[0].version, "1.40.0")
        XCTAssertEqual(versions[1].version, "1.39.4")
        XCTAssertTrue(versions.allSatisfy { $0.kind == .deno })
    }

    func testDecodeEmptyArrayReturnsEmpty() throws {
        let data = Data("[]".utf8)
        let versions = try DenoProvider.decode(data: data)
        XCTAssertEqual(versions.count, 0)
    }
}
