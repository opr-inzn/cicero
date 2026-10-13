// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The tests stay out of the public repository, so a clone builds without them.
let hasTests = FileManager.default.fileExists(atPath: Context.packageDirectory + "/Tests/CiceroCoreTests")

let package = Package(
    name: "Cicero",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Updates (see scripts/build-app.sh for how the framework gets into the app).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Fonts, the library, activation, coverage and user data. No UI; tested by CiceroCoreTests.
        .target(name: "CiceroCore", path: "Sources/CiceroCore"),
        // The app. Everything in it runs on the main actor unless it says otherwise.
        .executableTarget(
            name: "Cicero",
            dependencies: ["CiceroCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Cicero",
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // Sparkle.framework is embedded in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ] + (hasTests ? [
        .testTarget(name: "CiceroCoreTests", dependencies: ["CiceroCore"], path: "Tests/CiceroCoreTests"),
    ] : [])
)
