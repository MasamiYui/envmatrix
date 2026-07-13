import XCTest
@testable import EnvMatrix

final class ErlangProviderDecodingTests: XCTestCase {
    private let sampleJSON = """
    [
      {"tag_name": "OTP-26.2.1", "draft": false, "prerelease": false},
      {"tag_name": "OTP-25.3.2", "draft": false, "prerelease": false},
      {"tag_name": "xxx", "draft": false, "prerelease": false}
    ]
    """

    private let prereleaseJSON = """
    [
      {"tag_name": "OTP-27.0-rc1", "draft": false, "prerelease": true},
      {"tag_name": "OTP-26.2.1", "draft": false, "prerelease": false}
    ]
    """

    func testDecodeStripsOTPPrefix() throws {
        let data = Data(sampleJSON.utf8)
        let versions = try ErlangProvider.decode(data: data)
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions[0].version, "26.2.1")
        XCTAssertEqual(versions[1].version, "25.3.2")
    }

    func testDecodeFiltersPrerelease() throws {
        let data = Data(prereleaseJSON.utf8)
        let versions = try ErlangProvider.decode(data: data)
        XCTAssertEqual(versions.count, 1)
        XCTAssertEqual(versions[0].version, "26.2.1")
    }
}
