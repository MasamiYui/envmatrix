import XCTest
@testable import EnvMatrix

final class NodeProviderDecodingTests: XCTestCase {
    // Sample mimicking https://nodejs.org/dist/index.json with 12 entries.
    private let sampleJSON = """
    [
      {"version":"v21.6.0","date":"2024-01-14","files":["osx-arm64-tar","osx-x64-tar","linux-x64"],"lts":false},
      {"version":"v21.5.0","date":"2023-12-19","files":["osx-arm64-tar","osx-x64-tar"],"lts":false},
      {"version":"v20.11.0","date":"2024-01-09","files":["osx-arm64-tar","osx-x64-tar"],"lts":"Iron"},
      {"version":"v20.10.0","date":"2023-11-22","files":["osx-arm64-tar","osx-x64-tar"],"lts":"Iron"},
      {"version":"v20.9.0","date":"2023-10-24","files":["osx-arm64-tar","osx-x64-tar"],"lts":"Iron"},
      {"version":"v18.19.0","date":"2023-11-29","files":["osx-arm64-tar","osx-x64-tar"],"lts":"Hydrogen"},
      {"version":"v18.18.2","date":"2023-10-13","files":["osx-arm64-tar","osx-x64-tar"],"lts":"Hydrogen"},
      {"version":"v18.17.0","date":"2023-07-18","files":["osx-arm64-tar","osx-x64-tar"],"lts":"Hydrogen"},
      {"version":"v16.20.2","date":"2023-08-08","files":["osx-arm64-tar","osx-x64-tar"],"lts":"Gallium"},
      {"version":"v16.20.1","date":"2023-06-20","files":["osx-arm64-tar","osx-x64-tar"],"lts":"Gallium"},
      {"version":"v14.21.3","date":"2023-02-16","files":["osx-x64-tar"],"lts":"Fermium"},
      {"version":"v0.10.48","date":"2016-10-18","files":["linux-x64"],"lts":false}
    ]
    """

    func testDecodeArm64ReturnsAtLeastTen() throws {
        let data = Data(sampleJSON.utf8)
        let versions = try NodeProvider.decode(data: data, arch: "arm64")
        XCTAssertGreaterThanOrEqual(versions.count, 10,
                                    "Should decode at least 10 arm64 entries, got \(versions.count)")

        // Ensure version strings have no leading 'v'
        XCTAssertTrue(versions.allSatisfy { !$0.version.hasPrefix("v") })

        // Ensure downloadURL is set with expected pattern
        if let first = versions.first {
            XCTAssertNotNil(first.downloadURL)
            XCTAssertTrue(first.downloadURL!.absoluteString.contains("darwin-arm64.tar.gz"))
        }

        // At least one LTS marked
        XCTAssertTrue(versions.contains(where: { $0.isLTS }))
    }

    func testDecodeX64Filters() throws {
        let data = Data(sampleJSON.utf8)
        let versions = try NodeProvider.decode(data: data, arch: "x64")
        XCTAssertGreaterThanOrEqual(versions.count, 10)
        // v0.10.48 has no osx-x64-tar -> excluded
        XCTAssertFalse(versions.contains(where: { $0.version == "0.10.48" }))
    }

    func testInvalidJSONThrows() {
        let data = Data("not json".utf8)
        XCTAssertThrowsError(try NodeProvider.decode(data: data, arch: "arm64")) { error in
            guard case RuntimeServiceError.decoding = error else {
                XCTFail("Expected decoding error, got \(error)")
                return
            }
        }
    }
}
