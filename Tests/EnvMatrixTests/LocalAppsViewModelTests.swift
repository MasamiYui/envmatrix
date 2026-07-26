import XCTest
@testable import EnvMatrix

@MainActor
final class LocalAppsViewModelTests: XCTestCase {
    var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-vm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try await super.tearDown()
    }

    final class MockLocalAppsScanner: LocalAppsScanner {
        var apps: [LocalApp]
        init(apps: [LocalApp]) { self.apps = apps }
        func scan(roots: [URL]) async throws -> [LocalApp] { apps }
    }

    final class MockLocalAppsService: LocalAppsService {
        var moveToTrashCalls: [LocalApp] = []
        var scanLeftoversCalls: [String] = []
        var trashLeftoversCalls: [[LocalAppLeftover]] = []
        var openCalls: [LocalApp] = []
        var revealCalls: [LocalApp] = []
        var leftoversToReturn: [LocalAppLeftover] = []
        var protectedBundleIds: Set<String> = []
        var trashResultURL: URL?

        func openApp(_ app: LocalApp) throws { openCalls.append(app) }
        func revealInFinder(_ app: LocalApp) { revealCalls.append(app) }
        func moveToTrash(_ app: LocalApp) throws -> URL? {
            moveToTrashCalls.append(app)
            return trashResultURL
        }
        func scanLeftovers(bundleId: String) async -> [LocalAppLeftover] {
            scanLeftoversCalls.append(bundleId)
            return leftoversToReturn
        }
        func trashLeftovers(_ items: [LocalAppLeftover]) throws {
            trashLeftoversCalls.append(items)
        }
        func isProtected(_ app: LocalApp) -> Bool {
            protectedBundleIds.contains(app.bundleId)
        }
    }

    private func makeApp(
        name: String,
        bundleId: String,
        source: LocalAppSource = .other,
        sizeBytes: Int64 = 0
    ) -> LocalApp {
        LocalApp(
            name: name,
            displayName: name,
            version: "1.0",
            bundleId: bundleId,
            bundlePath: tempRoot.appendingPathComponent("\(name).app"),
            sizeBytes: sizeBytes,
            source: source,
            isProtected: false
        )
    }

    private func waitUntilNotBusy(_ vm: LocalAppsViewModel, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while vm.isBusy && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func waitUntil(
        _ vm: LocalAppsViewModel,
        timeout: TimeInterval = 3,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testRefreshLoadsAppsFromScanner() async throws {
        let apps = [
            makeApp(name: "Alpha", bundleId: "com.example.alpha", source: .appStore),
            makeApp(name: "Bravo", bundleId: "com.example.bravo", source: .brewCask(token: "bravo")),
            makeApp(name: "Charlie", bundleId: "com.example.charlie", source: .other)
        ]
        let scanner = MockLocalAppsScanner(apps: apps)
        let service = MockLocalAppsService()
        let vm = LocalAppsViewModel(scanner: scanner, service: service, roots: [tempRoot])

        vm.refresh()
        await waitUntilNotBusy(vm)

        XCTAssertEqual(vm.apps.count, 3)
        XCTAssertEqual(Set(vm.apps.map { $0.name }), Set(["Alpha", "Bravo", "Charlie"]))
    }

    func testSearchTextFiltersApps() async throws {
        let apps = [
            makeApp(name: "Alpha", bundleId: "com.example.alpha"),
            makeApp(name: "Bravo", bundleId: "com.example.bravo"),
            makeApp(name: "Charlie", bundleId: "com.example.charlie")
        ]
        let vm = LocalAppsViewModel(
            scanner: MockLocalAppsScanner(apps: apps),
            service: MockLocalAppsService(),
            roots: [tempRoot]
        )
        vm.refresh()
        await waitUntilNotBusy(vm)

        vm.searchText = "brav"
        XCTAssertEqual(vm.filteredApps.map { $0.name }, ["Bravo"])

        vm.searchText = "com.example.charlie"
        XCTAssertEqual(vm.filteredApps.map { $0.name }, ["Charlie"])

        vm.searchText = ""
        XCTAssertEqual(vm.filteredApps.count, 3)
    }

    func testSourceFilterNarrowsApps() async throws {
        let apps = [
            makeApp(name: "Alpha", bundleId: "com.example.alpha", source: .appStore),
            makeApp(name: "Bravo", bundleId: "com.example.bravo", source: .brewCask(token: "bravo")),
            makeApp(name: "Charlie", bundleId: "com.example.charlie", source: .other)
        ]
        let vm = LocalAppsViewModel(
            scanner: MockLocalAppsScanner(apps: apps),
            service: MockLocalAppsService(),
            roots: [tempRoot]
        )
        vm.refresh()
        await waitUntilNotBusy(vm)

        vm.sourceFilter = .appStore
        XCTAssertEqual(vm.filteredApps.map { $0.name }, ["Alpha"])

        vm.sourceFilter = .brewCask
        XCTAssertEqual(vm.filteredApps.map { $0.name }, ["Bravo"])

        vm.sourceFilter = .other
        XCTAssertEqual(vm.filteredApps.map { $0.name }, ["Charlie"])

        vm.sourceFilter = .all
        XCTAssertEqual(vm.filteredApps.count, 3)
    }

    func testConfirmUninstallInvokesMoveToTrashAndPopulatesLeftovers() async throws {
        let target = makeApp(name: "Bravo", bundleId: "com.example.bravo")
        let apps = [
            makeApp(name: "Alpha", bundleId: "com.example.alpha"),
            target,
            makeApp(name: "Charlie", bundleId: "com.example.charlie")
        ]
        let leftover = LocalAppLeftover(
            url: tempRoot.appendingPathComponent("Library/Preferences/com.example.bravo.plist"),
            sizeBytes: 100,
            kind: .preferences
        )
        let service = MockLocalAppsService()
        service.leftoversToReturn = [leftover]
        let vm = LocalAppsViewModel(
            scanner: MockLocalAppsScanner(apps: apps),
            service: service,
            roots: [tempRoot]
        )
        vm.refresh()
        await waitUntilNotBusy(vm)

        vm.requestUninstall(target)
        XCTAssertEqual(vm.pendingUninstall?.bundleId, "com.example.bravo")

        vm.confirmUninstall()
        await waitUntilNotBusy(vm)
        await waitUntil(vm) { !vm.pendingLeftovers.isEmpty }

        XCTAssertEqual(service.moveToTrashCalls.count, 1)
        XCTAssertEqual(service.moveToTrashCalls.first?.bundleId, "com.example.bravo")
        XCTAssertFalse(vm.apps.contains(where: { $0.bundleId == "com.example.bravo" }))
        XCTAssertEqual(vm.pendingLeftovers.count, 1)
        XCTAssertEqual(vm.lastUninstalledBundleId, "com.example.bravo")
    }

    func testConfirmLeftoverTrashInvokesServiceAndClearsPending() async throws {
        let target = makeApp(name: "Bravo", bundleId: "com.example.bravo")
        let leftover1 = LocalAppLeftover(
            url: tempRoot.appendingPathComponent("Library/Preferences/com.example.bravo.plist"),
            sizeBytes: 100,
            kind: .preferences
        )
        let leftover2 = LocalAppLeftover(
            url: tempRoot.appendingPathComponent("Library/Caches/com.example.bravo"),
            sizeBytes: 200,
            kind: .caches
        )
        let service = MockLocalAppsService()
        service.leftoversToReturn = [leftover1, leftover2]
        let vm = LocalAppsViewModel(
            scanner: MockLocalAppsScanner(apps: [target]),
            service: service,
            roots: [tempRoot]
        )
        vm.refresh()
        await waitUntilNotBusy(vm)

        vm.requestUninstall(target)
        vm.confirmUninstall()
        await waitUntilNotBusy(vm)
        await waitUntil(vm) { vm.pendingLeftovers.count == 2 }
        XCTAssertEqual(vm.pendingLeftovers.count, 2)

        let selection: Set<LocalAppLeftover.ID> = Set(vm.pendingLeftovers.prefix(1).map { $0.id })
        vm.confirmLeftoverTrash(selection: selection)
        await waitUntilNotBusy(vm)
        await waitUntil(vm) { vm.pendingLeftovers.isEmpty }

        XCTAssertEqual(service.trashLeftoversCalls.count, 1)
        XCTAssertEqual(service.trashLeftoversCalls.first?.count, 1)
        XCTAssertTrue(vm.pendingLeftovers.isEmpty)
    }
}
