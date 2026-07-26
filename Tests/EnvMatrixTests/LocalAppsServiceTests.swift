import XCTest
@testable import EnvMatrix

final class LocalAppsServiceTests: XCTestCase {
    var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-svc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    final class MockTrasher: Trasher {
        var calls: [URL] = []
        var shouldFail: Bool = false
        var resultURL: URL?
        func trash(_ url: URL) throws -> URL? {
            calls.append(url)
            if shouldFail {
                throw NSError(domain: "MockTrasher", code: 1)
            }
            return resultURL
        }
    }

    final class MockAppLauncher: AppLauncher {
        var opened: [URL] = []
        var revealed: [URL] = []
        var openShouldFail: Bool = false
        func open(_ url: URL) throws {
            if openShouldFail { throw LocalAppsError.openFailed }
            opened.append(url)
        }
        func reveal(_ url: URL) { revealed.append(url) }
    }

    private func makeApp(
        name: String = "Foo",
        bundleId: String = "com.example.foo",
        bundlePath: URL,
        isProtected: Bool = false
    ) -> LocalApp {
        LocalApp(
            name: name,
            displayName: name,
            version: "1.0",
            bundleId: bundleId,
            bundlePath: bundlePath,
            sizeBytes: 0,
            source: .other,
            isProtected: isProtected
        )
    }

    func testIsProtectedForSystemApplications() async throws {
        let svc = DefaultLocalAppsService(
            launcher: MockAppLauncher(),
            trasher: MockTrasher(),
            homeDirectory: tempRoot
        )
        let app = makeApp(
            bundleId: "com.example.foo",
            bundlePath: URL(fileURLWithPath: "/System/Applications/Foo.app")
        )
        XCTAssertTrue(svc.isProtected(app))
    }

    func testIsProtectedForRegularApplicationsFolder() async throws {
        let svc = DefaultLocalAppsService(
            launcher: MockAppLauncher(),
            trasher: MockTrasher(),
            homeDirectory: tempRoot
        )
        let app = makeApp(
            bundleId: "com.example.foo",
            bundlePath: URL(fileURLWithPath: "/Applications/Foo.app")
        )
        XCTAssertFalse(svc.isProtected(app))
    }

    func testIsProtectedForAppleBundleId() async throws {
        let svc = DefaultLocalAppsService(
            launcher: MockAppLauncher(),
            trasher: MockTrasher(),
            homeDirectory: tempRoot
        )
        let app = makeApp(
            bundleId: "com.apple.foo",
            bundlePath: URL(fileURLWithPath: "/Applications/Foo.app")
        )
        XCTAssertTrue(svc.isProtected(app))
    }

    func testMoveToTrashInvokesTrasherAndReturnsResultURL() async throws {
        let fm = FileManager.default
        let appPath = tempRoot.appendingPathComponent("Foo.app", isDirectory: true)
        try fm.createDirectory(at: appPath, withIntermediateDirectories: true)

        let trasher = MockTrasher()
        let expectedResult = tempRoot.appendingPathComponent("Trash/Foo.app")
        trasher.resultURL = expectedResult

        let svc = DefaultLocalAppsService(
            launcher: MockAppLauncher(),
            trasher: trasher,
            homeDirectory: tempRoot
        )
        let app = makeApp(bundleId: "com.example.foo", bundlePath: appPath)

        let returned = try svc.moveToTrash(app)
        XCTAssertEqual(returned, expectedResult)
        XCTAssertEqual(trasher.calls, [appPath])
    }

    func testMoveToTrashRejectsProtectedApp() async throws {
        let trasher = MockTrasher()
        let svc = DefaultLocalAppsService(
            launcher: MockAppLauncher(),
            trasher: trasher,
            homeDirectory: tempRoot
        )
        let app = makeApp(
            bundleId: "com.apple.foo",
            bundlePath: URL(fileURLWithPath: "/Applications/Foo.app")
        )
        XCTAssertThrowsError(try svc.moveToTrash(app))
        XCTAssertTrue(trasher.calls.isEmpty)
    }

    func testScanLeftoversFindsFilesInMockedLibrary() async throws {
        let fm = FileManager.default
        let library = tempRoot.appendingPathComponent("Library", isDirectory: true)
        let prefs = library.appendingPathComponent("Preferences", isDirectory: true)
        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        try fm.createDirectory(at: prefs, withIntermediateDirectories: true)
        try fm.createDirectory(at: caches, withIntermediateDirectories: true)

        let plistFile = prefs.appendingPathComponent("com.example.foo.plist")
        try Data("x".utf8).write(to: plistFile)

        let cacheDir = caches.appendingPathComponent("com.example.foo", isDirectory: true)
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data("y".utf8).write(to: cacheDir.appendingPathComponent("data.bin"))

        let svc = DefaultLocalAppsService(
            launcher: MockAppLauncher(),
            trasher: MockTrasher(),
            homeDirectory: tempRoot
        )
        let leftovers = await svc.scanLeftovers(bundleId: "com.example.foo")
        XCTAssertGreaterThanOrEqual(leftovers.count, 2)
        let kinds = Set(leftovers.map { $0.kind })
        XCTAssertTrue(kinds.contains(.preferences))
        XCTAssertTrue(kinds.contains(.caches))
    }

    func testScanLeftoversWithEmptyBundleIdReturnsEmpty() async throws {
        let svc = DefaultLocalAppsService(
            launcher: MockAppLauncher(),
            trasher: MockTrasher(),
            homeDirectory: tempRoot
        )
        let leftovers = await svc.scanLeftovers(bundleId: "")
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testTrashLeftoversInvokesTrasherForEachItem() async throws {
        let trasher = MockTrasher()
        let svc = DefaultLocalAppsService(
            launcher: MockAppLauncher(),
            trasher: trasher,
            homeDirectory: tempRoot
        )
        let items = [
            LocalAppLeftover(
                url: tempRoot.appendingPathComponent("a"),
                sizeBytes: 1,
                kind: .preferences
            ),
            LocalAppLeftover(
                url: tempRoot.appendingPathComponent("b"),
                sizeBytes: 2,
                kind: .caches
            ),
            LocalAppLeftover(
                url: tempRoot.appendingPathComponent("c"),
                sizeBytes: 3,
                kind: .logs
            )
        ]
        try svc.trashLeftovers(items)
        XCTAssertEqual(trasher.calls.count, 3)
        XCTAssertEqual(Set(trasher.calls), Set(items.map { $0.url }))
    }
}
