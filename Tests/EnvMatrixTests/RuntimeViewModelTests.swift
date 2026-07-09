import XCTest
@testable import EnvMatrix

@MainActor
final class RuntimeViewModelTests: XCTestCase {

    // MARK: - Mock

    final class MockRuntimeService: RuntimeService {
        var availableList: [RuntimeVersion] = []
        var installedList: [RuntimeVersion] = []
        var activeVersionValue: String? = nil

        // Optional hook invoked during install (after first progress callback fires).
        // Runs on the main actor so tests can inspect the VM's state.
        var midInstallHook: (@MainActor () -> Void)?

        func listAvailable(kind: RuntimeKind) async throws -> [RuntimeVersion] {
            return availableList
        }

        func listInstalled(kind: RuntimeKind) throws -> [RuntimeVersion] {
            return installedList
        }

        func install(version: RuntimeVersion, progress: @escaping (Double) -> Void) async throws {
            progress(0.5)
            if let hook = midInstallHook {
                await MainActor.run { hook() }
            }
            // Yield to let the VM process the first progress update.
            await Task.yield()
            progress(1.0)
            // Simulate the service now knowing about the newly installed version.
            if !installedList.contains(where: { $0.version == version.version }) {
                installedList.append(version)
            }
        }

        func activate(version: RuntimeVersion) throws {
            activeVersionValue = version.version
        }

        func uninstall(version: RuntimeVersion) throws {
            installedList.removeAll { $0.version == version.version }
            if activeVersionValue == version.version {
                activeVersionValue = nil
            }
        }

        func currentActive(kind: RuntimeKind) -> String? {
            return activeVersionValue
        }
    }

    // MARK: - Helpers

    private func makeVersion(_ v: String, kind: RuntimeKind = .node) -> RuntimeVersion {
        RuntimeVersion(kind: kind, version: v)
    }

    // MARK: - Tests

    func testInstallUpdatesProgressAndInstallingSetAndRefreshes() async throws {
        let mock = MockRuntimeService()
        mock.installedList = []
        let vm = RuntimeViewModel(kind: .node, service: mock)

        let v = makeVersion("20.0.0")

        var sawInstalling = false
        var sawProgress = false
        mock.midInstallHook = { [weak vm] in
            guard let vm = vm else { return }
            if vm.installingVersionIDs.contains(v.id) {
                sawInstalling = true
            }
            if let p = vm.installProgress[v.id], p > 0 {
                sawProgress = true
            }
        }

        await vm.install(v)

        XCTAssertTrue(sawInstalling, "installingVersionIDs should contain the id during install")
        XCTAssertTrue(sawProgress, "installProgress should be updated during install")

        // After completion the set is cleared.
        XCTAssertFalse(vm.installingVersionIDs.contains(v.id))

        // Final progress should be 1.0 (or at least > 0).
        let finalProgress = vm.installProgress[v.id] ?? 0
        XCTAssertGreaterThan(finalProgress, 0)
        XCTAssertEqual(finalProgress, 1.0, accuracy: 0.0001)

        // Mock updates its own listInstalled result -> vm.installed reflects it.
        XCTAssertTrue(vm.installed.contains(where: { $0.version == "20.0.0" }))
    }

    func testActivateUpdatesActiveVersion() throws {
        let mock = MockRuntimeService()
        let v = makeVersion("18.17.0")
        mock.installedList = [v]
        let vm = RuntimeViewModel(kind: .node, service: mock)

        vm.refreshInstalled()
        XCTAssertNil(vm.activeVersion)

        vm.activate(v)

        XCTAssertEqual(vm.activeVersion, "18.17.0")
        XCTAssertTrue(vm.installed.contains(where: { $0.version == "18.17.0" }))
    }

    func testUninstallRemovesVersionAndClearsActive() throws {
        let mock = MockRuntimeService()
        let v = makeVersion("18.17.0")
        mock.installedList = [v]
        mock.activeVersionValue = v.version
        let vm = RuntimeViewModel(kind: .node, service: mock)

        vm.refreshInstalled()
        XCTAssertEqual(vm.activeVersion, "18.17.0")
        XCTAssertEqual(vm.installed.count, 1)

        vm.uninstall(v)

        XCTAssertFalse(vm.installed.contains(where: { $0.version == "18.17.0" }))
        XCTAssertNil(vm.activeVersion)
    }
}
