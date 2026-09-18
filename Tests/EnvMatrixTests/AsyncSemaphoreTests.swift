import XCTest
@testable import EnvMatrix

final class AsyncSemaphoreTests: XCTestCase {
    actor TimestampCollector {
        private(set) var starts: [(Int, TimeInterval)] = []
        private(set) var ends: [(Int, TimeInterval)] = []

        func recordStart(_ index: Int, _ time: TimeInterval) {
            starts.append((index, time))
        }

        func recordEnd(_ index: Int, _ time: TimeInterval) {
            ends.append((index, time))
        }

        func sortedStarts() -> [(Int, TimeInterval)] {
            starts.sorted { $0.1 < $1.1 }
        }
    }

    func testSemaphoreLimitsConcurrency() async {
        let semaphore = AsyncSemaphore(permits: 2)
        let collector = TimestampCollector()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<3 {
                group.addTask {
                    await semaphore.wait()
                    let startTime = Date().timeIntervalSince1970
                    await collector.recordStart(i, startTime)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    let endTime = Date().timeIntervalSince1970
                    await collector.recordEnd(i, endTime)
                    await semaphore.signal()
                }
            }
        }

        let sorted = await collector.sortedStarts()
        XCTAssertEqual(sorted.count, 3)
        let firstStart = sorted[0].1
        let thirdStart = sorted[2].1
        let delta = thirdStart - firstStart
        XCTAssertGreaterThanOrEqual(delta, 0.150)
    }
}
