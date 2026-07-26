import XCTest
@testable import EnvMatrix

@MainActor
final class ShellEnvViewModelTests: XCTestCase {
    private enum TestError: Error { case fake }

    private final class FakeShellEnvService: ShellEnvService {
        var files: [ShellRcFile] = []
        var contents: [ShellRcKind: String] = [:]
        var readError: Error?
        var writeError: Error?
        var backupURLToReturn: URL?
        private(set) var writtenText: [ShellRcKind: String] = [:]
        var currentShell: ShellRcKind? = .zshrc

        func availableFiles() -> [ShellRcFile] { files }

        func read(_ file: ShellRcFile) throws -> String {
            if let error = readError { throw error }
            return contents[file.kind] ?? ""
        }

        @discardableResult
        func write(_ file: ShellRcFile, text: String) throws -> URL? {
            if let error = writeError { throw error }
            writtenText[file.kind] = text
            contents[file.kind] = text
            return backupURLToReturn
        }

        func currentShellKind() -> ShellRcKind? { currentShell }
    }

    private func makeZshrcFile() -> ShellRcFile {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(".zshrc")
        return ShellRcFile(kind: .zshrc, url: url, exists: true, isCurrentShell: true)
    }

    private func waitUntilNotBusy(_ vm: ShellEnvViewModel, timeout: TimeInterval = 2.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while vm.isBusy && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testRoundTripStructuredRaw() async {
        let fake = FakeShellEnvService()
        let file = makeZshrcFile()
        fake.files = [file]
        fake.contents[.zshrc] = "export FOO=\"bar\"\n"

        let vm = ShellEnvViewModel(service: fake)
        vm.refresh()
        await waitUntilNotBusy(vm)

        let serializedBefore = ShellEnvParser.serialize(vm.document)
        vm.switchMode(to: .raw)
        vm.switchMode(to: .structured)
        XCTAssertEqual(ShellEnvParser.serialize(vm.document), serializedBefore)
    }

    func testSaveWritesAndClearsError() async {
        let fake = FakeShellEnvService()
        let file = makeZshrcFile()
        fake.files = [file]
        fake.contents[.zshrc] = "OLD"

        let vm = ShellEnvViewModel(service: fake)
        vm.refresh()
        await waitUntilNotBusy(vm)

        vm.switchMode(to: .raw)
        vm.rawText = "NEW"
        vm.save()
        await waitUntilNotBusy(vm)

        XCTAssertEqual(fake.writtenText[.zshrc], "NEW")
        XCTAssertNil(vm.errorMessage)
    }

    func testSaveErrorSetsMessageAndPreservesBuffer() async {
        let fake = FakeShellEnvService()
        let file = makeZshrcFile()
        fake.files = [file]
        fake.contents[.zshrc] = "OLD"

        let vm = ShellEnvViewModel(service: fake)
        vm.refresh()
        await waitUntilNotBusy(vm)

        fake.writeError = TestError.fake
        vm.switchMode(to: .raw)
        vm.rawText = "PARTIAL"
        vm.save()
        await waitUntilNotBusy(vm)

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(vm.rawText, "PARTIAL")
    }
}
