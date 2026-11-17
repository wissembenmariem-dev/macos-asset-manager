// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AssetManager",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AssetManager",
            path: "Sources/AssetManager",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("Foundation")
            ]
        ),
        .testTarget(
            name: "AssetManagerTests",
            dependencies: ["AssetManager"],
            path: "Tests/AssetManagerTests"
        )
    ]
)
