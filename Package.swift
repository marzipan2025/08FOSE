// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FontGrid",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FontGrid",
            path: "Sources/FontGrid",
            resources: [
                .copy("Resources/AppIcon.png"),
                .copy("Resources/Wallpapers"),
                // The asset catalog used to sit at 08FOSE/Assets.xcassets,
                // outside this target, so only the Xcode app target compiled
                // it — assets were simply missing from the SwiftPM product and
                // rendered blank whenever the package scheme was run. It now
                // lives here and both build systems read the one catalog
                // (the app target points at this same path).
                .process("Resources/Assets.xcassets")
            ]
        )
    ]
)
