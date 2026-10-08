// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pipa",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Pipa",
            path: "Sources/Pipa",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
