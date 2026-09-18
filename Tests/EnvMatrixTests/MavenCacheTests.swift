import XCTest
@testable import EnvMatrix

final class MavenCacheTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MavenCacheTests-\(UUID().uuidString)", isDirectory: true)
        let versionDir = root
            .appendingPathComponent("com", isDirectory: true)
            .appendingPathComponent("example", isDirectory: true)
            .appendingPathComponent("foo", isDirectory: true)
            .appendingPathComponent("1.0.0", isDirectory: true)
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        let pom = versionDir.appendingPathComponent("foo-1.0.0.pom")
        FileManager.default.createFile(atPath: pom.path, contents: Data())
        tempRoot = root
    }

    override func tearDownWithError() throws {
        if let root = tempRoot {
            try? FileManager.default.removeItem(at: root)
        }
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testScanCachesResults() throws {
        let service = DefaultMavenLocalRepositoryService(
            repositoryURL: tempRoot,
            fileSystemWatcher: nil
        )
        _ = try service.scan()
        _ = try service.scan()
        XCTAssertEqual(service.scanCount, 1)
    }

    func testInvalidateCacheClears() throws {
        let service = DefaultMavenLocalRepositoryService(
            repositoryURL: tempRoot,
            fileSystemWatcher: nil
        )
        _ = try service.scan()
        service.invalidateCache()
        _ = try service.scan()
        XCTAssertEqual(service.scanCount, 2)
    }

    func testWatcherInvalidatesCache() throws {
        let watcher = MockFileSystemWatcher()
        let service = DefaultMavenLocalRepositoryService(
            repositoryURL: tempRoot,
            fileSystemWatcher: watcher
        )
        _ = try service.scan()
        XCTAssertEqual(service.scanCount, 1)

        let onChange = try XCTUnwrap(watcher.capturedOnChange)
        onChange([FileSystemChange(path: tempRoot.path, flags: 0)])
        Thread.sleep(forTimeInterval: 0.05)

        _ = try service.scan()
        XCTAssertEqual(service.scanCount, 2)
    }
}

private final class MockFileSystemWatcher: FileSystemWatcher {
    var capturedOnChange: (([FileSystemChange]) -> Void)?

    func watch(
        paths: [String],
        latency: TimeInterval,
        debounceInterval: TimeInterval,
        onChange: @escaping ([FileSystemChange]) -> Void
    ) -> WatchHandle {
        capturedOnChange = onChange
        return WatchHandle(onInvalidate: {})
    }
}
