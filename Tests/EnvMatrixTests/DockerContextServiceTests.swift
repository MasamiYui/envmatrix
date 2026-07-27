import XCTest
@testable import EnvMatrix

final class MockProcessExecutor: ProcessExecutor {
    struct Call {
        let executable: URL
        let args: [String]
        let timeout: TimeInterval?
    }
    var calls: [Call] = []
    var responses: [(ProcessResult)?] = []

    func run(executable: URL, args: [String], timeout: TimeInterval?) async throws -> ProcessResult {
        calls.append(Call(executable: executable, args: args, timeout: timeout))
        let idx = calls.count - 1
        if idx < responses.count {
            if let r = responses[idx] { return r }
            throw ProcessExecutorError.timeout
        }
        return ProcessResult(stdout: "", stderr: "", exitCode: 0)
    }
}

final class StubShellPathResolver: ShellPathResolver {
    let dirs: [URL]
    init(dirs: [URL]) { self.dirs = dirs }
    func resolvePathDirs() -> [URL] { dirs }
}

enum DockerTestFixtures {
    static func makeTempBinDir(binaryName: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("envmatrix-\(binaryName)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bin = root.appendingPathComponent(binaryName)
        let script = "#!/bin/sh\nexit 0\n"
        try script.data(using: .utf8)!.write(to: bin, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        return root
    }
}

// Tests for DefaultDockerContextService argument construction and parsing.
final class DockerContextServiceTests: XCTestCase {
    var tempBinDir: URL!
    var executor: MockProcessExecutor!
    var service: DefaultDockerContextService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempBinDir = try DockerTestFixtures.makeTempBinDir(binaryName: "docker")
        executor = MockProcessExecutor()
        service = DefaultDockerContextService(
            executor: executor,
            shellPathResolver: StubShellPathResolver(dirs: [tempBinDir]),
            fileManager: .default
        )
    }

    override func tearDownWithError() throws {
        if let tempBinDir = tempBinDir,
           FileManager.default.fileExists(atPath: tempBinDir.path) {
            try? FileManager.default.removeItem(at: tempBinDir)
        }
        try super.tearDownWithError()
    }

    func test_listContexts_parsesThreeJSONLines_andHighlightsCurrent() async throws {
        let stdout = """
{"Name":"default","Description":"Current DOCKER_HOST based configuration","DockerEndpoint":"unix:///var/run/docker.sock","ContextType":"moby","Current":false}
{"Name":"colima","Description":"colima","DockerEndpoint":"unix:///Users/me/.colima/default/docker.sock","ContextType":"moby","Current":true}
{"Name":"remote","Description":"","DockerEndpoint":"tcp://1.2.3.4:2376","ContextType":"moby","Current":false}
"""
        executor.responses = [ProcessResult(stdout: stdout, stderr: "", exitCode: 0)]
        let result = try await service.listContexts()
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[1].name, "colima")
        XCTAssertTrue(result[1].isCurrent)
        XCTAssertFalse(result[0].isCurrent)
        XCTAssertFalse(result[2].isCurrent)
    }

    func test_useContext_sendsExactArgs() async throws {
        executor.responses = [ProcessResult(stdout: "", stderr: "", exitCode: 0)]
        try await service.useContext("colima")
        XCTAssertEqual(executor.calls.count, 1)
        XCTAssertEqual(executor.calls.last?.args, ["context", "use", "colima"])
    }

    func test_createContext_withTLS_buildsHostSpec() async throws {
        executor.responses = [ProcessResult(stdout: "", stderr: "", exitCode: 0)]
        let tls = DockerTLSOptions(
            caCert: "/tmp/ca.pem",
            clientCert: "/tmp/cert.pem",
            clientKey: "/tmp/key.pem",
            skipVerify: true
        )
        try await service.createContext(
            name: "remote",
            host: "tcp://1.2.3.4:2376",
            description: "prod",
            tls: tls
        )
        let args = executor.calls.last?.args ?? []
        XCTAssertEqual(args.first, "context")
        XCTAssertTrue(args.contains("create"))
        XCTAssertTrue(args.contains("remote"))
        XCTAssertTrue(args.contains("--docker"))
        guard let dockerIdx = args.firstIndex(of: "--docker") else {
            return XCTFail("Missing --docker flag")
        }
        let spec = args[dockerIdx + 1]
        XCTAssertTrue(spec.contains("host=tcp://1.2.3.4:2376"), "spec=\(spec)")
        XCTAssertTrue(spec.contains("ca=/tmp/ca.pem"), "spec=\(spec)")
        XCTAssertTrue(spec.contains("cert=/tmp/cert.pem"), "spec=\(spec)")
        XCTAssertTrue(spec.contains("key=/tmp/key.pem"), "spec=\(spec)")
        XCTAssertTrue(spec.contains("skip-tls-verify=true"), "spec=\(spec)")
        guard let descIdx = args.firstIndex(of: "--description") else {
            return XCTFail("Missing --description flag")
        }
        XCTAssertEqual(args[descIdx + 1], "prod")
    }

    func test_updateContext_nothingToUpdate_throwsInvalidInput() async {
        do {
            try await service.updateContext(name: "x", host: nil, description: nil, tls: nil)
            XCTFail("Expected invalidInput")
        } catch let error as ContainerContextsError {
            switch error {
            case .invalidInput:
                break
            default:
                XCTFail("Expected invalidInput, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_removeContext_defaultProtected() async {
        do {
            try await service.removeContext("default")
            XCTFail("Expected invalidInput")
        } catch let error as ContainerContextsError {
            switch error {
            case .invalidInput:
                break
            default:
                XCTFail("Expected invalidInput, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_ping_timeout_mapsToDockerTimeout() async {
        executor.responses = [nil]
        do {
            _ = try await service.ping("colima", timeout: 1)
            XCTFail("Expected timeout")
        } catch let error as ContainerContextsError {
            switch error {
            case .timeout(let engine):
                XCTAssertEqual(engine, .docker)
            default:
                XCTFail("Expected timeout(.docker), got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_listContexts_invalidJSON_throwsParseFailed() async {
        executor.responses = [ProcessResult(stdout: "notJSON", stderr: "", exitCode: 0)]
        do {
            _ = try await service.listContexts()
            XCTFail("Expected parseFailed")
        } catch let error as ContainerContextsError {
            switch error {
            case .parseFailed(let engine, let snippet):
                XCTAssertEqual(engine, .docker)
                XCTAssertTrue(snippet.contains("notJSON"), "snippet=\(snippet)")
            default:
                XCTFail("Expected parseFailed(.docker), got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
