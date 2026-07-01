// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "lazy-tuple-builder",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "lazy-tuple-builder",
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes"),
                .enableExperimentalFeature("SuppressedAssociatedTypes"),
            ]
        )
    ]
)
