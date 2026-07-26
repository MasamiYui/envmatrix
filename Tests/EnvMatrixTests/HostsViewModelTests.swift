import XCTest
@testable import EnvMatrix

@MainActor
final class HostsViewModelTests: XCTestCase {
    var tempRoot: URL!
    var systemHostsURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-hosts-vm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        systemHostsURL = tempRoot.appendingPathComponent("etc-hosts")
        try "127.0.0.1 localhost\n".data(using: .utf8)!.write(to: systemHostsURL, options: .atomic)
    }

    override func tearDown() async throws {
        if let tempRoot = tempRoot,
           FileManager.default.fileExists(atPath: tempRoot.path) {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try await super.tearDown()
    }

    private func makeVM() -> HostsViewModel {
        let writer = HostsServiceTests.MockWriter()
        let service = DefaultHostsService(
            baseDirectory: tempRoot.appendingPathComponent("appsupport", isDirectory: true),
            systemHostsPath: systemHostsURL.path,
            writer: writer
        )
        return HostsViewModel(service: service)
    }

    private func waitUntilNotBusy(_ vm: HostsViewModel, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while vm.isBusy && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testRefreshCreatesDefaultProfileFromSystem() async throws {
        let vm = makeVM()
        vm.refresh()
        await waitUntilNotBusy(vm)
        XCTAssertEqual(vm.profiles.count, 1)
        XCTAssertEqual(vm.profiles.first?.name, "default")
        XCTAssertEqual(vm.rawText, "127.0.0.1 localhost\n")
        XCTAssertTrue(vm.systemMatchesCurrentProfile)
    }

    func testAddEntryAndSerialize() async throws {
        let vm = makeVM()
        vm.refresh()
        await waitUntilNotBusy(vm)

        vm.addEntry()
        XCTAssertTrue(vm.document.lines.contains(where: {
            if case .entry = $0 { return true }
            return false
        }))

        vm.switchMode(to: .raw)
        XCTAssertTrue(vm.rawText.contains("example.local"))
    }

    func testToggleEnabledReflectsInRaw() async throws {
        let vm = makeVM()
        vm.refresh()
        await waitUntilNotBusy(vm)
        vm.addEntry()
        guard case .entry(let e) = vm.document.lines.last! else {
            return XCTFail("Expected entry")
        }
        vm.updateEntry(id: e.id, isEnabled: false)
        vm.switchMode(to: .raw)
        XCTAssertTrue(vm.rawText.contains("#127.0.0.1 example.local"))
    }

    func testSaveProfileWritesToDisk() async throws {
        let vm = makeVM()
        vm.refresh()
        await waitUntilNotBusy(vm)
        vm.addEntry()
        vm.saveProfile()
        await waitUntilNotBusy(vm)

        let url = vm.selection!.url
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("example.local"))
    }

    func testApplyToSystemWritesViaMockWriter() async throws {
        let vm = makeVM()
        vm.refresh()
        await waitUntilNotBusy(vm)
        vm.switchMode(to: .raw)
        vm.rawText = "8.8.8.8 dns.local\n"
        vm.applyToSystem()
        await waitUntilNotBusy(vm)
        let text = try String(contentsOf: systemHostsURL, encoding: .utf8)
        XCTAssertEqual(text, "8.8.8.8 dns.local\n")
        XCTAssertNotNil(vm.lastBackupURL)
    }
}
