// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "embedded-style-extensions",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "embedded-style-extensions",
            swiftSettings: [
                .enableExperimentalFeature("Embedded"),
                .enableExperimentalFeature("Lifetimes"),
                .enableExperimentalFeature("SuppressedAssociatedTypes"),
                .unsafeFlags(["-wmo"]),
            ]
        )
    ]
)
