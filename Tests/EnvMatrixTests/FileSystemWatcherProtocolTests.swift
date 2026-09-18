import XCTest
@testable import EnvMatrix

final class FileSystemWatcherProtocolTests: XCTestCase {
    func testNoopWatcherReturnsHandleImmediately() {
        let watcher = NoopFileSystemWatcher()
        let handle = watcher.watch(
            paths: ["/tmp"],
            latency: 0.5,
            debounceInterval: 0.25,
            onChange: { _ in }
        )
        XCTAssertNotNil(handle)
    }

    func testInvalidateIsIdempotent() {
        let watcher = NoopFileSystemWatcher()
        let handle = watcher.watch(
            paths: ["/tmp"],
            latency: 0.5,
            debounceInterval: 0.25,
            onChange: { _ in }
        )
        handle.invalidate()
        handle.invalidate()
        XCTAssertNotNil(handle)
    }

    func testWatchHandleInvalidateCallsClosureOnce() {
        var counter = 0
        let handle = WatchHandle(onInvalidate: {
            counter += 1
        })
        handle.invalidate()
        handle.invalidate()
        XCTAssertEqual(counter, 1)
    }
}
