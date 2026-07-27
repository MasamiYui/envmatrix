import XCTest
@testable import EnvMatrix

final class ContainerImagesModelsTests: XCTestCase {
    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func testContainerImageCodableRoundTrip() throws {
        let image = ContainerImage(
            id: "sha256:abc",
            repository: "nginx",
            tag: "latest",
            digest: "sha256:deadbeef",
            sizeBytes: 12_345_678,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            engine: .docker
        )
        let data = try makeEncoder().encode(image)
        let decoded = try makeDecoder().decode(ContainerImage.self, from: data)
        XCTAssertEqual(decoded, image)
    }

    func testContainerInstanceCodableRoundTrip() throws {
        let instance = ContainerInstance(
            id: "c1",
            names: ["web", "web2"],
            image: "nginx:latest",
            command: "nginx -g 'daemon off;'",
            state: .running,
            status: "Up 2 hours",
            portsSummary: "0.0.0.0:80->80/tcp",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            engine: .podman
        )
        let data = try makeEncoder().encode(instance)
        let decoded = try makeDecoder().decode(ContainerInstance.self, from: data)
        XCTAssertEqual(decoded, instance)
    }

    func testContainerInstanceStateFromUnknownFallsBackToUnknown() {
        XCTAssertEqual(ContainerInstanceState.from("weird"), .unknown)
        XCTAssertEqual(ContainerInstanceState.from("Running"), .running)
        XCTAssertEqual(ContainerInstanceState.from("EXITED"), .exited)
    }

    func testContainerInstanceStateDecodesUnknownRawValue() throws {
        let data = Data("\"weird\"".utf8)
        let state = try JSONDecoder().decode(ContainerInstanceState.self, from: data)
        XCTAssertEqual(state, .unknown)
    }
}
