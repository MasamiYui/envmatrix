// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EnvMatrix",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "EnvMatrix",
            path: "Sources/EnvMatrix",
            resources: [
                .copy("Resources/AppIcon.icns")
            ]
        ),
        .testTarget(
            name: "EnvMatrixTests",
            dependencies: ["EnvMatrix"],
            path: "Tests/EnvMatrixTests"
        )
    ]
)
