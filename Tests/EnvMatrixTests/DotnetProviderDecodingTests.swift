import XCTest
@testable import EnvMatrix

final class DotnetProviderDecodingTests: XCTestCase {
    private let sampleJSON = """
    {
      "releases-index": [
        {
          "channel-version": "8.0",
          "latest-sdk": "8.0.100",
          "latest-runtime": "8.0.0",
          "support-phase": "active"
        },
        {
          "channel-version": "7.0",
          "latest-sdk": "7.0.404",
          "latest-runtime": "7.0.14",
          "support-phase": "eol"
        }
      ]
    }
    """

    private let malformedJSON = """
    {
      "releases-index": [
        {
          "channel-version": "8.0",
          "latest-sdk": "8.0.100",
          "latest-runtime": "8.0.0",
          "support-phase": "active"
        },
        {
          "channel-version": "6.0",
          "latest-runtime": "6.0.25",
          "support-phase": "eol"
        }
      ]
    }
    """

    func testDecodeReturnsLatestSdk() throws {
        let data = Data(sampleJSON.utf8)
        let versions = try DotnetProvider.decode(data: data)
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions[0].version, "8.0.100")
        XCTAssertTrue(versions[0].isLTS)
        XCTAssertEqual(versions[1].version, "7.0.404")
        XCTAssertFalse(versions[1].isLTS)
    }

    func testDecodeIgnoresMalformedEntry() throws {
        let data = Data(malformedJSON.utf8)
        let versions = try DotnetProvider.decode(data: data)
        XCTAssertEqual(versions.count, 1)
        XCTAssertEqual(versions[0].version, "8.0.100")
        XCTAssertTrue(versions[0].isLTS)
    }
}
