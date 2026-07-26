import XCTest
@testable import EnvMatrix

@MainActor
final class ProjectEnvViewModelTests: XCTestCase {

    // Build a synthetic environment for pure ViewModel logic tests. Everything
    // is in-memory — we never touch the disk.
    private func makeEnv(
        name: String,
        size: Int64?,
        mtime: Date?,
        kind: ProjectEnvKind = .nodeModules
    ) -> ProjectEnvironment {
        let root = URL(fileURLWithPath: "/tmp/envmatrix-tests/\(name)")
        let envURL = root.appendingPathComponent(kind == .venv ? ".venv" : "node_modules")
        return ProjectEnvironment(
            kind: kind,
            url: envURL,
            projectRoot: root,
            sizeBytes: size,
            pythonVersion: nil,
            packageManager: nil,
            modifiedAt: mtime
        )
    }

    // MARK: - Sorting

    func testVisibleEnvironmentsSortOrders() {
        let vm = ProjectEnvViewModel()

        let now = Date()
        let dayAgo = now.addingTimeInterval(-1 * 86_400)
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let yearAgo = now.addingTimeInterval(-365 * 86_400)

        let a = makeEnv(name: "alpha",  size: 100_000_000, mtime: dayAgo)   // big + fresh
        let b = makeEnv(name: "beta",   size: 10_000_000,  mtime: yearAgo)  // small + very old
        let c = makeEnv(name: "gamma",  size: 50_000_000,  mtime: weekAgo)  // mid + week old

        vm.environments = [b, a, c]

        vm.sortOption = .sizeDesc
        XCTAssertEqual(vm.visibleEnvironments.map(\.id), [a, c, b].map(\.id),
                       "sizeDesc should list biggest first")

        vm.sortOption = .sizeAsc
        XCTAssertEqual(vm.visibleEnvironments.map(\.id), [b, c, a].map(\.id),
                       "sizeAsc should list smallest first")

        vm.sortOption = .mtimeAsc
        XCTAssertEqual(vm.visibleEnvironments.map(\.id), [b, c, a].map(\.id),
                       "mtimeAsc should list oldest first")

        vm.sortOption = .mtimeDesc
        XCTAssertEqual(vm.visibleEnvironments.map(\.id), [a, c, b].map(\.id),
                       "mtimeDesc should list newest first")
    }

    func testKindFilterAndMinSizeStillApply() {
        let vm = ProjectEnvViewModel()
        let now = Date()

        let big  = makeEnv(name: "big",  size: 200_000_000, mtime: now, kind: .nodeModules)
        let mid  = makeEnv(name: "mid",  size:  50_000_000, mtime: now, kind: .nodeModules)
        let venv = makeEnv(name: "vv",   size: 100_000_000, mtime: now, kind: .venv)

        vm.environments = [big, mid, venv]

        vm.sortOption = .sizeDesc
        vm.kindFilter = .nodeModules
        vm.minSizeMB = 100 // 100 MB
        // Only `big` (200 MB, nodeModules) survives.
        XCTAssertEqual(vm.visibleEnvironments.map(\.id), [big.id])

        vm.kindFilter = .venv
        vm.minSizeMB = 0
        XCTAssertEqual(vm.visibleEnvironments.map(\.id), [venv.id])
    }

    // MARK: - Health

    func testHealthBuckets() {
        let now = Date()
        let tenDaysAgo   = now.addingTimeInterval(-10  * 86_400)
        let ninetyDaysAgo = now.addingTimeInterval(-90  * 86_400)
        let fourHundred   = now.addingTimeInterval(-400 * 86_400)

        let active    = makeEnv(name: "a", size: 1, mtime: tenDaysAgo)
        let idle      = makeEnv(name: "b", size: 1, mtime: ninetyDaysAgo)
        let abandoned = makeEnv(name: "c", size: 1, mtime: fourHundred)
        let missing   = makeEnv(name: "d", size: 1, mtime: nil)

        XCTAssertEqual(ProjectEnvViewModel.health(for: active, now: now), .active)
        XCTAssertEqual(ProjectEnvViewModel.health(for: idle, now: now), .idle)
        XCTAssertEqual(ProjectEnvViewModel.health(for: abandoned, now: now), .abandoned)
        XCTAssertEqual(ProjectEnvViewModel.health(for: missing, now: now), .abandoned)
    }

    func testAbandonedTotalBytesAndBulkList() {
        let vm = ProjectEnvViewModel()
        let now = Date()
        let fresh = makeEnv(name: "fresh", size: 1_000, mtime: now)
        let old1  = makeEnv(name: "old1",  size: 2_000, mtime: now.addingTimeInterval(-400 * 86_400))
        let old2  = makeEnv(name: "old2",  size: 3_000, mtime: nil)

        vm.environments = [fresh, old1, old2]

        let ids = Set(vm.abandonedEnvironments.map(\.id))
        XCTAssertEqual(ids, Set([old1.id, old2.id]))
        XCTAssertEqual(vm.abandonedTotalBytes, 5_000)
    }
}
