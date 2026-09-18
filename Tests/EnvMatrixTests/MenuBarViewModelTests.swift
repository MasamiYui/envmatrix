import XCTest
@testable import EnvMatrix

final class MenuBarViewModelTests: XCTestCase {
    private final class StubRuntimeService: RuntimeService {
        var installed: [RuntimeKind: [RuntimeVersion]] = [:]
        var active: [RuntimeKind: String] = [:]
        private(set) var activated: [RuntimeVersion] = []
        var activateError: Error?

        func listAvailable(kind: RuntimeKind) async throws -> [RuntimeVersion] { [] }
        func listInstalled(kind: RuntimeKind) throws -> [RuntimeVersion] { installed[kind] ?? [] }
        func install(version: RuntimeVersion, progress: @escaping (Double) -> Void) async throws {}
        func activate(version: RuntimeVersion) throws {
            if let activateError { throw activateError }
            activated.append(version)
            active[version.kind] = version.version
        }
        func uninstall(version: RuntimeVersion) throws {}
        func currentActive(kind: RuntimeKind) -> String? { active[kind] }
        func invalidateSystemCaches() {}
    }

    private func version(_ kind: RuntimeKind, _ v: String, system: Bool = false) -> RuntimeVersion {
        RuntimeVersion(kind: kind, version: v, installPath: URL(fileURLWithPath: "/tmp/\(v)"), isSystem: system)
    }

    @MainActor
    func testRefreshSkipsRuntimesWithNoVersionsAndFlagsSwitchable() async {
        let service = StubRuntimeService()
        service.installed[.node] = [version(.node, "18.19.0"), version(.node, "20.11.0")]
        service.installed[.go] = [version(.go, "1.22.0", system: true)]
        service.active[.node] = "20.11.0"

        let vm = MenuBarViewModel(service: service)
        await vm.refresh()

        XCTAssertEqual(vm.items.map { $0.kind }, [.node, .go])
        let node = vm.items.first { $0.kind == .node }!
        XCTAssertEqual(node.active, "20.11.0")
        XCTAssertTrue(node.isSwitchable)
        // A single installed version is shown but not expandable.
        XCTAssertFalse(vm.items.first { $0.kind == .go }!.isSwitchable)
    }

    @MainActor
    func testActivateSwitchesAndRefreshes() async {
        let service = StubRuntimeService()
        service.installed[.node] = [version(.node, "18.19.0"), version(.node, "20.11.0")]
        service.active[.node] = "20.11.0"
        let vm = MenuBarViewModel(service: service)
        await vm.refresh()

        await vm.activate(version(.node, "18.19.0"))

        XCTAssertEqual(service.activated.map { $0.version }, ["18.19.0"])
        XCTAssertEqual(vm.items.first { $0.kind == .node }?.active, "18.19.0")
        XCTAssertNil(vm.switchingKind)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func testActivateSurfacesErrors() async {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "no permission" } }
        let service = StubRuntimeService()
        service.installed[.node] = [version(.node, "18.19.0")]
        service.activateError = Boom()
        let vm = MenuBarViewModel(service: service)

        await vm.activate(version(.node, "18.19.0"))

        XCTAssertEqual(vm.errorMessage, "no permission")
        XCTAssertNil(vm.switchingKind)
    }

    @MainActor
    func testRefreshIfStaleHonoursTTL() async {
        let service = StubRuntimeService()
        service.installed[.node] = [version(.node, "20.11.0")]
        let vm = MenuBarViewModel(service: service)

        await vm.refreshIfStale()
        let firstLoad = vm.loadedAt
        XCTAssertNotNil(firstLoad)

        service.installed[.go] = [version(.go, "1.22.0")]
        await vm.refreshIfStale()
        XCTAssertEqual(vm.loadedAt, firstLoad, "second call within the TTL must not re-scan")

        await vm.refreshIfStale(force: true)
        XCTAssertEqual(vm.items.count, 2)
    }
}
