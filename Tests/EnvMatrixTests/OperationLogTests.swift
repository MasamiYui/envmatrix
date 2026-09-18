import XCTest
@testable import EnvMatrix

final class OperationLogTests: XCTestCase {
    private struct NoopPrivilegedWriter: HostsPrivilegedWriter {
        func write(source: URL, to systemPath: String) throws {}
    }

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-oplog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    @MainActor
    private func makeLog() -> OperationLog {
        OperationLog(storeURL: tmp.appendingPathComponent("ops.json"), privilegedWriter: NoopPrivilegedWriter())
    }

    @MainActor
    func testRecordPersistsAndReloads() {
        let log = makeLog()
        log.record(.registry, title: "Switched npm registry", detail: "https://registry.npmmirror.com")
        XCTAssertEqual(log.entries.count, 1)

        let reloaded = makeLog()
        XCTAssertEqual(reloaded.entries.first?.title, "Switched npm registry")
        XCTAssertEqual(reloaded.entries.first?.category, .registry)
    }

    @MainActor
    func testRollbackRestoresBackupAndKeepsSafetyCopy() throws {
        let target = tmp.appendingPathComponent(".npmrc")
        let backup = tmp.appendingPathComponent(".npmrc.envmatrix.bak")
        try "registry=https://registry.npmmirror.com\n".write(to: target, atomically: true, encoding: .utf8)
        try "registry=https://registry.npmjs.org/\n".write(to: backup, atomically: true, encoding: .utf8)

        let log = makeLog()
        let entry = log.record(.registry, title: "Switched npm registry", target: target, backup: backup)
        XCTAssertTrue(log.canRollback(entry))

        try log.rollback(entry)

        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "registry=https://registry.npmjs.org/\n")
        XCTAssertNotNil(log.entries.first { $0.id == entry.id }?.rolledBackAt)
        XCTAssertFalse(log.canRollback(log.entries.first { $0.id == entry.id }!), "already rolled back")
        // The rollback itself is logged and carries a safety copy of the overwritten file.
        let rollbackEntry = log.entries.first!
        XCTAssertTrue(rollbackEntry.title.contains("Switched npm registry"))
        XCTAssertNotNil(rollbackEntry.backupPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollbackEntry.backupPath!))
    }

    @MainActor
    func testEntriesWithoutBackupCannotRollback() {
        let log = makeLog()
        let entry = log.record(.runtime, title: "Activated Node 20")
        XCTAssertFalse(log.canRollback(entry))
        XCTAssertThrowsError(try log.rollback(entry))
    }

    @MainActor
    func testCapsAtMaxEntries() {
        let log = makeLog()
        for i in 0..<(OperationLog.maxEntries + 20) {
            log.record(.other, title: "op \(i)")
        }
        XCTAssertEqual(log.entries.count, OperationLog.maxEntries)
        XCTAssertEqual(log.entries.first?.title, "op \(OperationLog.maxEntries + 19)")
    }

    func testLatestBackupPicksNewest() throws {
        let a = tmp.appendingPathComponent("uv.toml.20240101-000000.bak")
        let b = tmp.appendingPathComponent("uv.toml.20240102-000000.bak")
        try "a".write(to: a, atomically: true, encoding: .utf8)
        try "b".write(to: b, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: a.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: b.path)
        XCTAssertEqual(OperationLog.latestBackup(in: tmp, prefix: "uv.toml.", suffix: ".bak")?.lastPathComponent,
                       b.lastPathComponent)
        XCTAssertNil(OperationLog.latestBackup(in: tmp, prefix: "nope.", suffix: ".bak"))
    }
}
