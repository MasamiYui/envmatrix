import XCTest
@testable import EnvMatrix

@MainActor
final class LogStoreTests: XCTestCase {
    func testLogAppendsEntries() {
        let store = LogStore()
        store.log(.info, "hello")
        store.log(.info, "hello")
        store.log(.info, "hello")
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries.last?.message, "hello")
    }

    func testTruncationAt500Entries() {
        let store = LogStore()
        for i in 0..<550 {
            store.log(.info, "msg-\(i)")
        }
        XCTAssertEqual(store.entries.count, 500)
        // The oldest 50 entries should be dropped; the last message is "msg-549".
        XCTAssertEqual(store.entries.last?.message, "msg-549")
        XCTAssertEqual(store.entries.first?.message, "msg-50")
    }

    func testClearRemovesAllEntries() {
        let store = LogStore()
        store.log(.warning, "one")
        store.log(.error, "two")
        XCTAssertEqual(store.entries.count, 2)
        store.clear()
        XCTAssertEqual(store.entries.count, 0)
    }
}
