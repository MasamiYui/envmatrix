import XCTest
@testable import EnvMatrix

final class GoProviderDecodingTests: XCTestCase {
    private let sampleJSON = """
    [
      {
        "version": "go1.22.0",
        "stable": true,
        "files": [
          {"filename":"go1.22.0.darwin-arm64.tar.gz","os":"darwin","arch":"arm64","kind":"archive","sha256":"abc"},
          {"filename":"go1.22.0.darwin-amd64.tar.gz","os":"darwin","arch":"amd64","kind":"archive","sha256":"def"},
          {"filename":"go1.22.0.linux-amd64.tar.gz","os":"linux","arch":"amd64","kind":"archive","sha256":"ghi"}
        ]
      },
      {
        "version": "go1.21.6",
        "stable": true,
        "files": [
          {"filename":"go1.21.6.darwin-arm64.tar.gz","os":"darwin","arch":"arm64","kind":"archive","sha256":"a"},
          {"filename":"go1.21.6.darwin-amd64.pkg","os":"darwin","arch":"amd64","kind":"installer","sha256":"b"}
        ]
      },
      {
        "version": "go1.20.14",
        "stable": true,
        "files": [
          {"filename":"go1.20.14.darwin-amd64.tar.gz","os":"darwin","arch":"amd64","kind":"archive","sha256":"c"}
        ]
      }
    ]
    """

    func testDecodeArm64() throws {
        let data = Data(sampleJSON.utf8)
        let versions = try GoProvider.decode(data: data, arch: "arm64")
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions.first?.version, "1.22.0")
        XCTAssertNotNil(versions.first?.downloadURL)
        XCTAssertTrue(versions.first!.downloadURL!.absoluteString.contains("darwin-arm64.tar.gz"))
    }

    func testDecodeAmd64() throws {
        let data = Data(sampleJSON.utf8)
        let versions = try GoProvider.decode(data: data, arch: "amd64")
        // go1.21.6 has amd64 only as installer (kind=installer), so it's filtered out.
        // Only go1.22.0 and go1.20.14 have amd64 archives.
        XCTAssertEqual(versions.count, 2)
        XCTAssertTrue(versions.allSatisfy { !$0.version.hasPrefix("go") })
    }

    func testInvalidJSONThrows() {
        let data = Data("bad".utf8)
        XCTAssertThrowsError(try GoProvider.decode(data: data, arch: "arm64")) { error in
            guard case RuntimeServiceError.decoding = error else {
                XCTFail("Expected decoding error, got \(error)")
                return
            }
        }
    }
}
