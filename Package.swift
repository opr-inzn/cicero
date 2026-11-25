// swift-tools-version: 6.2
import Foundation
import PackageDescription

let hasTests = FileManager.default.fileExists(atPath: Context.packageDirectory + "/Tests/CiceroCoreTests")

let package = Package(
    name: "Cicero",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", exact: "0.12.1"),
    ],
    targets: [
        .target(name: "CiceroCore", path: "Sources/CiceroCore"),
        .target(name: "CiceroCommands", dependencies: ["CiceroCore"], path: "Sources/CiceroCommands"),
        // Built as cicero-tool because a binary named cicero collides with the Cicero app on a case-insensitive disk.
        .executableTarget(
            name: "cicero-tool",
            dependencies: [
                "CiceroCommands",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/CiceroTool"
        ),
        .executableTarget(
            name: "Cicero",
            dependencies: ["CiceroCore", "CiceroCommands", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Cicero",
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ] + (hasTests ? [
        .testTarget(name: "CiceroCoreTests", dependencies: ["CiceroCore"], path: "Tests/CiceroCoreTests"),
    ] : [])
)
