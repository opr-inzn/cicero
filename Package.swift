// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The tests stay out of the public repository, so a clone builds without them.
let hasTests = FileManager.default.fileExists(atPath: Context.packageDirectory + "/Tests/CiceroCoreTests")

let package = Package(
    name: "Cicero",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Updates (see scripts/build-app.sh for how the framework gets into the app).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        // The `cicero` command's arguments, help and shell completions.
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
    ],
    targets: [
        // Fonts, the library, activation, coverage and user data. No UI; tested by CiceroCoreTests.
        .target(name: "CiceroCore", path: "Sources/CiceroCore"),
        // The `cicero` command's commands as functions, input to result value, and the JSON they answer in. No printing.
        .target(name: "CiceroCommands", dependencies: ["CiceroCore"], path: "Sources/CiceroCommands"),
        // The `cicero` command-line tool: arguments, printing for people and --json. Built as cicero-tool, as a binary
        // named cicero would be the app's on a disk that ignores case; it goes in the bundle as Contents/Helpers/cicero.
        .executableTarget(
            name: "cicero-tool",
            dependencies: ["CiceroCommands", .product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "Sources/CiceroTool"
        ),
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
