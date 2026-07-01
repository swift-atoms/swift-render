// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "generic-rendering-context",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "generic-rendering-context",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableExperimentalFeature("Lifetimes"),
                .enableExperimentalFeature("SuppressedAssociatedTypes"),
            ]
        )
    ]
)
