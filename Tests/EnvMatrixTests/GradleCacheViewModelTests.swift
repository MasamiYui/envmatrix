import XCTest
@testable import EnvMatrix

@MainActor
final class GradleCacheViewModelTests: XCTestCase {

    private let fm = FileManager.default
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = fm.temporaryDirectory
            .appendingPathComponent("GradleCacheViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot = tempRoot, fm.fileExists(atPath: tempRoot.path) {
            try? fm.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeArtifact(
        id: String,
        group: String = "com.example",
        artifact: String = "lib",
        version: String = "1.0.0",
        url: URL? = nil,
        size: Int64,
        mtime: Date?
    ) -> GradleArtifact {
        GradleArtifact(
            id: id,
            group: group,
            artifact: artifact,
            version: version,
            url: url ?? URL(fileURLWithPath: "/tmp/\(id)"),
            sizeBytes: size,
            modifiedAt: mtime
        )
    }

    // MARK: - Sort

    func testVisibleArtifactsSortOrders() {
        let vm = GradleCacheViewModel()
        let now = Date()
        let a = makeArtifact(id: "a", size: 100, mtime: now.addingTimeInterval(-3_600))       // 1h ago
        let b = makeArtifact(id: "b", size: 500, mtime: now.addingTimeInterval(-86_400))       // 1d ago
        let c = makeArtifact(id: "c", size: 300, mtime: now)                                   // now
        vm.artifacts = [a, b, c]

        vm.artifactSort = .sizeDesc
        XCTAssertEqual(vm.visibleArtifacts.map(\.id), ["b", "c", "a"])

        vm.artifactSort = .sizeAsc
        XCTAssertEqual(vm.visibleArtifacts.map(\.id), ["a", "c", "b"])

        vm.artifactSort = .mtimeDesc
        XCTAssertEqual(vm.visibleArtifacts.map(\.id), ["c", "a", "b"])

        vm.artifactSort = .mtimeAsc
        XCTAssertEqual(vm.visibleArtifacts.map(\.id), ["b", "a", "c"])
    }

    // MARK: - Search filter

    func testArtifactSearchFilter() {
        let vm = GradleCacheViewModel()
        let slf4jApi = makeArtifact(
            id: "org.slf4j:slf4j-api:2.0.0",
            group: "org.slf4j",
            artifact: "slf4j-api",
            version: "2.0.0",
            size: 1_000,
            mtime: Date()
        )
        let guava = makeArtifact(
            id: "com.google.guava:guava:32.1.0",
            group: "com.google.guava",
            artifact: "guava",
            version: "32.1.0",
            size: 2_000,
            mtime: Date()
        )
        let slf4jSimple = makeArtifact(
            id: "org.slf4j:slf4j-simple:2.0.7",
            group: "org.slf4j",
            artifact: "slf4j-simple",
            version: "2.0.7",
            size: 500,
            mtime: Date()
        )
        vm.artifacts = [slf4jApi, guava, slf4jSimple]

        vm.artifactSearch = "slf4j"
        XCTAssertEqual(vm.visibleArtifacts.count, 2)

        vm.artifactSearch = "guava"
        XCTAssertEqual(vm.visibleArtifacts.count, 1)
        XCTAssertEqual(vm.visibleArtifacts.first?.artifact, "guava")

        vm.artifactSearch = "2.0.7"
        XCTAssertEqual(vm.visibleArtifacts.count, 1)
        XCTAssertEqual(vm.visibleArtifacts.first?.version, "2.0.7")

        vm.artifactSearch = "   "
        XCTAssertEqual(vm.visibleArtifacts.count, 3)
    }

    // MARK: - Delete

    func testDeleteArtifactsMutatesState() async throws {
        let vm = GradleCacheViewModel()

        // Create three real directories on disk so trashItem has something to
        // operate on. Each one contains a small payload file.
        var artifacts: [GradleArtifact] = []
        for i in 0..<3 {
            let dir = tempRoot.appendingPathComponent("art-\(i)", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let payload = dir.appendingPathComponent("payload.bin")
            try Data(repeating: UInt8(i), count: 64).write(to: payload)
            artifacts.append(
                makeArtifact(
                    id: "grp:art:\(i)",
                    artifact: "art-\(i)",
                    version: "\(i)",
                    url: dir,
                    size: 64,
                    mtime: Date()
                )
            )
        }
        vm.artifacts = artifacts
        vm.selectedArtifactIDs = Set(artifacts.map(\.id))

        await vm.deleteArtifacts(vm.selectedArtifactIDs)

        // Happy-path contract: on a normal macOS dev machine `trashItem`
        // succeeds, everything is removed from the in-memory list, the
        // selection set is cleared, and the on-disk directories are gone.
        //
        // CI-fallback contract: on a sandboxed CI runner without Finder,
        // `trashItem` may fail for every URL. In that case the spec allows
        // `artifacts` to be non-empty, but `errorMessage` must be surfaced.
        if vm.errorMessage == nil {
            XCTAssertTrue(vm.artifacts.isEmpty)
            XCTAssertTrue(vm.selectedArtifactIDs.isEmpty)
            for art in artifacts {
                XCTAssertFalse(
                    fm.fileExists(atPath: art.url.path),
                    "\(art.url.path) should have been moved to Trash"
                )
            }
        } else {
            XCTAssertFalse(vm.errorMessage?.isEmpty ?? true)
        }
    }
}
