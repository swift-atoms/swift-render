// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "conditional-copyable-conformance",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "conditional-copyable-conformance",
            swiftSettings: [
                .enableExperimentalFeature("Lifetimes"),
                .enableExperimentalFeature("SuppressedAssociatedTypes"),
            ]
        )
    ]
)
