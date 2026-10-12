// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Point",
    platforms: [.macOS(.v26)],
    targets: [
        // Fonts, the library, activation, coverage and user data. No UI; tested by PointCoreTests.
        .target(name: "PointCore", path: "Sources/PointCore"),
        // The app. Everything in it runs on the main actor unless it says otherwise.
        .executableTarget(
            name: "Point",
            dependencies: ["PointCore"],
            path: "Sources/Point",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "PointCoreTests", dependencies: ["PointCore"], path: "Tests/PointCoreTests"),
    ]
)
