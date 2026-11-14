// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnapClip",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SnapClipCore", targets: ["SnapClipCore"]),
        .library(name: "SnapClipUI", targets: ["SnapClipUI"]),
        .executable(name: "snapclip", targets: ["SnapClipCLI"])
    ],
    targets: [
        .target(
            name: "SnapClipCore",
            dependencies: []
        ),
        .target(
            name: "SnapClipUI",
            dependencies: ["SnapClipCore"]
        ),
        .executableTarget(
            name: "SnapClipCLI",
            dependencies: ["SnapClipCore", "SnapClipUI"]
        ),
        .testTarget(
            name: "SnapClipCoreTests",
            dependencies: ["SnapClipCore"]
        )
    ]
)
