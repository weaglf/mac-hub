// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Hub",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Hub",
            path: "Sources/Hub",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
