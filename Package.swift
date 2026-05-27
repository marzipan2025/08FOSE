// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FontGrid",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FontGrid",
            path: "Sources/FontGrid"
        )
    ]
)
