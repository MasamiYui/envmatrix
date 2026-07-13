import XCTest
@testable import EnvMatrix

final class PhpProviderDecodingTests: XCTestCase {
    private let sampleJSON = """
    {
      "8.3": {
        "version": "8.3.0",
        "date": "2023-11-23",
        "source": [{"filename": "php-8.3.0.tar.gz"}]
      },
      "8.2": {
        "version": "8.2.13",
        "date": "2023-11-23",
        "source": [{"filename": "php-8.2.13.tar.gz"}]
      },
      "8.1": {
        "version": "8.1.26",
        "date": "2023-11-23",
        "source": [{"filename": "php-8.1.26.tar.gz"}]
      }
    }
    """

    func testDecodeReturnsTopReleases() throws {
        let data = Data(sampleJSON.utf8)
        let versions = try PhpProvider.decode(data: data)
        XCTAssertEqual(versions.count, 3)
        let regex = try NSRegularExpression(pattern: #"^\d+\.\d+\.\d+$"#)
        for v in versions {
            let range = NSRange(v.version.startIndex..<v.version.endIndex, in: v.version)
            XCTAssertNotNil(
                regex.firstMatch(in: v.version, range: range),
                "\(v.version) should match semver"
            )
            XCTAssertNotNil(v.downloadURL)
            XCTAssertTrue(
                v.downloadURL!.absoluteString
                    .contains("www.php.net/distributions/php-\(v.version).tar.gz")
            )
        }
        XCTAssertEqual(versions[0].version, "8.3.0")
        XCTAssertEqual(versions[1].version, "8.2.13")
        XCTAssertEqual(versions[2].version, "8.1.26")
    }

    func testDecodeInvalidJSONThrowsDecoding() {
        let data = Data("not json".utf8)
        XCTAssertThrowsError(try PhpProvider.decode(data: data)) { error in
            guard case RuntimeServiceError.decoding = error else {
                XCTFail("Expected decoding error, got \(error)")
                return
            }
        }
    }

    func testDecodeNetworkErrorPropagates() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PhpMockURLProtocol.self]
        let session = URLSession(configuration: config)
        let url = URL(string: "https://example.invalid/php")!

        PhpMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, Data())
        }
        defer { PhpMockURLProtocol.handler = nil }

        let provider = PhpProvider(session: session, indexURL: url)
        do {
            _ = try await provider.listAvailable()
            XCTFail("Expected network error")
        } catch let RuntimeServiceError.network(msg) {
            XCTAssertTrue(msg.contains("500"), "Expected 500 in message, got \(msg)")
        } catch {
            XCTFail("Expected RuntimeServiceError.network, got \(error)")
        }
    }
}

final class PhpMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = PhpMockURLProtocol.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(domain: "PhpMockURLProtocol", code: -1)
            )
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
