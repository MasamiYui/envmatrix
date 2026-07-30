import XCTest
@testable import EnvMatrix

final class KotlinProviderDecodingTests: XCTestCase {
    private let fixtureJSON = """
    [
      {
        "tag_name": "v2.0.0",
        "draft": false,
        "prerelease": false,
        "published_at": "2024-05-21T10:00:00Z",
        "assets": [
          {
            "name": "kotlin-compiler-2.0.0.zip",
            "browser_download_url": "https://github.com/JetBrains/kotlin/releases/download/v2.0.0/kotlin-compiler-2.0.0.zip"
          }
        ]
      },
      {
        "tag_name": "v1.9.24",
        "draft": false,
        "prerelease": false,
        "published_at": "2024-05-07T12:30:00Z",
        "assets": [
          {
            "name": "kotlin-native-macos-1.9.24.tar.gz",
            "browser_download_url": "https://example.com/native.tar.gz"
          },
          {
            "name": "kotlin-compiler-1.9.24.zip",
            "browser_download_url": "https://github.com/JetBrains/kotlin/releases/download/v1.9.24/kotlin-compiler-1.9.24.zip"
          }
        ]
      },
      {
        "tag_name": "v2.0.20-RC",
        "draft": false,
        "prerelease": true,
        "published_at": "2024-07-15T09:00:00Z",
        "assets": [
          {
            "name": "kotlin-compiler-2.0.20-RC.zip",
            "browser_download_url": "https://github.com/JetBrains/kotlin/releases/download/v2.0.20-RC/kotlin-compiler-2.0.20-RC.zip"
          }
        ]
      },
      {
        "tag_name": "v2.0.10-Beta1",
        "draft": false,
        "prerelease": true,
        "published_at": "2024-06-10T09:00:00Z",
        "assets": [
          {
            "name": "kotlin-compiler-2.0.10-Beta1.zip",
            "browser_download_url": "https://github.com/JetBrains/kotlin/releases/download/v2.0.10-Beta1/kotlin-compiler-2.0.10-Beta1.zip"
          }
        ]
      },
      {
        "tag_name": "v1.9.99-draft",
        "draft": true,
        "prerelease": false,
        "published_at": "2024-04-01T09:00:00Z",
        "assets": [
          {
            "name": "kotlin-compiler-1.9.99-draft.zip",
            "browser_download_url": "https://github.com/JetBrains/kotlin/releases/download/v1.9.99-draft/kotlin-compiler-1.9.99-draft.zip"
          }
        ]
      },
      {
        "tag_name": "v1.9.23",
        "draft": false,
        "prerelease": false,
        "published_at": "2024-03-20T08:15:00Z",
        "assets": [
          {
            "name": "kotlin-compiler-1.9.23.zip",
            "browser_download_url": "https://github.com/JetBrains/kotlin/releases/download/v1.9.23/kotlin-compiler-1.9.23.zip"
          }
        ]
      }
    ]
    """

    func testDecodeFiltersPrereleaseAndDraft() throws {
        let data = Data(fixtureJSON.utf8)
        let versions = try KotlinProvider.decode(data: data)
        XCTAssertEqual(versions.count, 3)
        XCTAssertTrue(versions.allSatisfy { $0.kind == .kotlin })
        let versionStrings = versions.map { $0.version }
        XCTAssertEqual(versionStrings, ["2.0.0", "1.9.24", "1.9.23"])
    }

    func testDecodeDownloadURLs() throws {
        let data = Data(fixtureJSON.utf8)
        let versions = try KotlinProvider.decode(data: data)
        XCTAssertFalse(versions.isEmpty)
        for version in versions {
            XCTAssertNotNil(version.downloadURL)
            let urlString = version.downloadURL?.absoluteString ?? ""
            XCTAssertTrue(urlString.contains("kotlin-compiler-"),
                          "downloadURL should contain 'kotlin-compiler-': \(urlString)")
            XCTAssertTrue(urlString.contains(".zip"),
                          "downloadURL should contain '.zip': \(urlString)")
            XCTAssertEqual(version.arch, "universal")
            XCTAssertFalse(version.isLTS)
        }
    }

    func testDecodeInvalidJSONThrows() {
        let data = Data("not json".utf8)
        XCTAssertThrowsError(try KotlinProvider.decode(data: data)) { error in
            guard let runtimeError = error as? RuntimeServiceError else {
                XCTFail("Expected RuntimeServiceError but got \(error)")
                return
            }
            switch runtimeError {
            case .decoding:
                break
            default:
                XCTFail("Expected .decoding case but got \(runtimeError)")
            }
        }
    }
}
