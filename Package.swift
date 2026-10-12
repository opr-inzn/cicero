// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Point",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Point",
            path: "Sources/Point",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
