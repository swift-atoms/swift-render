// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "embedded-rendering-context",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "embedded-rendering-context",
            swiftSettings: [
                .enableExperimentalFeature("Embedded"),
                .enableExperimentalFeature("Lifetimes"),
                .enableExperimentalFeature("SuppressedAssociatedTypes"),
                .unsafeFlags(["-wmo"]),
            ]
        )
    ]
)
