// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Cicero",
    platforms: [.macOS(.v26)],
    targets: [
        // Fonts, the library, activation, coverage and user data. No UI; tested by CiceroCoreTests.
        .target(name: "CiceroCore", path: "Sources/CiceroCore"),
        // The app. Everything in it runs on the main actor unless it says otherwise.
        .executableTarget(
            name: "Cicero",
            dependencies: ["CiceroCore"],
            path: "Sources/Cicero",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "CiceroCoreTests", dependencies: ["CiceroCore"], path: "Tests/CiceroCoreTests"),
    ]
)
