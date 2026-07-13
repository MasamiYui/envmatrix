import XCTest
@testable import EnvMatrix

final class RubyProviderDecodingTests: XCTestCase {
    func testDecodeParsesStableAndSkipsPreview() throws {
        let fixture = """
        ruby/3.3/ruby-3.3.0.tar.gz\t2023-12-25\t10\tSHA512\taaa
        ruby/3.2/ruby-3.2.3.tar.gz\t2024-01-18\t10\tSHA512\tbbb
        ruby/3.3/ruby-3.3.0-preview1.tar.gz\t2023-05-12\t10\tSHA512\tccc
        ruby/3.3/ruby-3.3.0.zip\t2023-12-25\t10\tSHA512\tddd
        """
        let data = Data(fixture.utf8)
        let versions = try RubyProvider.decode(data: data)
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions[0].version, "3.3.0")
        XCTAssertEqual(versions[1].version, "3.2.3")
        XCTAssertNotNil(versions[0].downloadURL)
        XCTAssertNotNil(versions[1].downloadURL)
        XCTAssertTrue(
            versions[0].downloadURL!.absoluteString
                .contains("/pub/ruby/3.3/ruby-3.3.0.tar.gz")
        )
        XCTAssertTrue(
            versions[1].downloadURL!.absoluteString
                .contains("/pub/ruby/3.2/ruby-3.2.3.tar.gz")
        )
    }

    func testDecodeSortsDescending() throws {
        let fixture = """
        ruby/3.2/ruby-3.2.3.tar.gz\t2024-01-18\t10\tSHA512\tbbb
        ruby/3.3/ruby-3.3.0.tar.gz\t2023-12-25\t10\tSHA512\taaa
        ruby/3.2/ruby-3.2.2.tar.gz\t2023-03-30\t10\tSHA512\tccc
        """
        let data = Data(fixture.utf8)
        let versions = try RubyProvider.decode(data: data)
        XCTAssertEqual(versions.map { $0.version }, ["3.3.0", "3.2.3", "3.2.2"])
    }

    func testDecodeDeduplicates() throws {
        let fixture = """
        ruby/3.3/ruby-3.3.0.tar.gz\t2023-12-25\t10\tSHA512\taaa
        ruby/3.3/ruby-3.3.0.tar.gz\t2023-12-25\t10\tSHA512\taaa
        """
        let data = Data(fixture.utf8)
        let versions = try RubyProvider.decode(data: data)
        XCTAssertEqual(versions.count, 1)
        XCTAssertEqual(versions[0].version, "3.3.0")
    }
}
