import XCTest
@testable import EnvMatrix

final class AppServicesTests: XCTestCase {
    func testSharedReturnsSameInstance() {
        let a = AppServices.shared
        let b = AppServices.shared
        XCTAssertTrue(a === b)
    }

    func testFileSystemWatcherAndProcessPoolAreNonNil() {
        let services = AppServices.shared
        XCTAssertNotNil(services.fileSystemWatcher)
        XCTAssertNotNil(services.processPool)
    }

    func testProcessPoolMaxConcurrentIsPositive() {
        XCTAssertGreaterThanOrEqual(AppServices.shared.processPoolMaxConcurrent, 1)
        XCTAssertNotNil(AppServices.shared.fileSystemWatcher)
    }
}
