import XCTest
@testable import EnvMatrix

final class LocalAppsScannerTests: XCTestCase {
    var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-scanner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        try makeFakeAppBundle(
            named: "MyApp.app",
            bundleName: "MyApp",
            bundleId: "com.example.myapp",
            version: "1.2.3",
            includeMASReceipt: false
        )
        try makeFakeAppBundle(
            named: "StoreApp.app",
            bundleName: "StoreApp",
            bundleId: "com.example.storeapp",
            version: "2.0.0",
            includeMASReceipt: true
        )
        try makeFakeAppBundle(
            named: "OtherApp.app",
            bundleName: "OtherApp",
            bundleId: "com.example.otherapp",
            version: "0.9",
            includeMASReceipt: false
        )
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    final class MockBrewCaskProbe: BrewCaskProbe {
        let map: [String: String]
        init(map: [String: String]) { self.map = map }
        func caskTokenMap() async -> [String: String] { map }
    }

    private func makeFakeAppBundle(
        named appDirName: String,
        bundleName: String,
        bundleId: String,
        version: String,
        includeMASReceipt: Bool
    ) throws {
        let fm = FileManager.default
        let appURL = tempRoot.appendingPathComponent(appDirName, isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleName": bundleName,
            "CFBundleIdentifier": bundleId,
            "CFBundleShortVersionString": version
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)

        if includeMASReceipt {
            let receiptDir = contents.appendingPathComponent("_MASReceipt", isDirectory: true)
            try fm.createDirectory(at: receiptDir, withIntermediateDirectories: true)
            try Data([0x00]).write(to: receiptDir.appendingPathComponent("receipt"), options: .atomic)
        }
    }

    func testScanReturnsThreeAppsWithCorrectMetadata() async throws {
        let probe = MockBrewCaskProbe(map: ["myapp.app": "myapp"])
        let scanner = DefaultLocalAppsScanner(probe: probe)
        let apps = try await scanner.scan(roots: [tempRoot])

        XCTAssertEqual(apps.count, 3)

        let byName = Dictionary(uniqueKeysWithValues: apps.map { ($0.name, $0) })

        let my = try XCTUnwrap(byName["MyApp"])
        XCTAssertEqual(my.version, "1.2.3")
        XCTAssertEqual(my.bundleId, "com.example.myapp")

        let store = try XCTUnwrap(byName["StoreApp"])
        XCTAssertEqual(store.version, "2.0.0")
        XCTAssertEqual(store.bundleId, "com.example.storeapp")

        let other = try XCTUnwrap(byName["OtherApp"])
        XCTAssertEqual(other.version, "0.9")
        XCTAssertEqual(other.bundleId, "com.example.otherapp")
    }

    func testScanIdentifiesAppStoreSource() async throws {
        let probe = MockBrewCaskProbe(map: ["myapp.app": "myapp"])
        let scanner = DefaultLocalAppsScanner(probe: probe)
        let apps = try await scanner.scan(roots: [tempRoot])

        let store = try XCTUnwrap(apps.first(where: { $0.name == "StoreApp" }))
        if case .appStore = store.source {
        } else {
            XCTFail("Expected .appStore, got \(store.source)")
        }
    }

    func testScanIdentifiesBrewCaskSourceFromMap() async throws {
        let probe = MockBrewCaskProbe(map: ["myapp.app": "myapp"])
        let scanner = DefaultLocalAppsScanner(probe: probe)
        let apps = try await scanner.scan(roots: [tempRoot])

        let my = try XCTUnwrap(apps.first(where: { $0.name == "MyApp" }))
        if case .brewCask(let token) = my.source {
            XCTAssertEqual(token, "myapp")
        } else {
            XCTFail("Expected .brewCask, got \(my.source)")
        }
    }

    func testScanIdentifiesOtherSource() async throws {
        let probe = MockBrewCaskProbe(map: ["myapp.app": "myapp"])
        let scanner = DefaultLocalAppsScanner(probe: probe)
        let apps = try await scanner.scan(roots: [tempRoot])

        let other = try XCTUnwrap(apps.first(where: { $0.name == "OtherApp" }))
        if case .other = other.source {
        } else {
            XCTFail("Expected .other, got \(other.source)")
        }
    }

    func testScanWithEmptyRootsReturnsEmpty() async throws {
        let probe = MockBrewCaskProbe(map: [:])
        let scanner = DefaultLocalAppsScanner(probe: probe)
        let apps = try await scanner.scan(roots: [])
        XCTAssertEqual(apps, [])
    }

    func testPerformanceScan200Apps() async throws {
        let perfRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-scanner-perf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: perfRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: perfRoot) }

        let count = 200
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<count {
                group.addTask {
                    try Self.writeFakeAppBundle(
                        root: perfRoot,
                        named: "PerfApp\(i).app",
                        bundleName: "PerfApp\(i)",
                        bundleId: "com.example.perfapp\(i)",
                        version: "1.0.\(i)"
                    )
                }
            }
            try await group.waitForAll()
        }

        let probe = MockBrewCaskProbe(map: [:])
        let scanner = DefaultLocalAppsScanner(probe: probe)

        let start = Date()
        let apps = try await scanner.scan(roots: [perfRoot])
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(apps.count, count)
        XCTAssertLessThan(elapsed, 5.0, "scan of \(count) apps took \(elapsed)s")
        print("PERF testPerformanceScan200Apps elapsed=\(elapsed)s count=\(apps.count)")
    }

    static func writeFakeAppBundle(
        root: URL,
        named appDirName: String,
        bundleName: String,
        bundleId: String,
        version: String
    ) throws {
        let fm = FileManager.default
        let appURL = root.appendingPathComponent(appDirName, isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleName": bundleName,
            "CFBundleIdentifier": bundleId,
            "CFBundleShortVersionString": version
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
    }
}
