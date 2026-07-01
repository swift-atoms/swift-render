// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "borrowing-pattern-matching",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "borrowing-pattern-matching",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableExperimentalFeature("Lifetimes"),
                .enableExperimentalFeature("SuppressedAssociatedTypes"),
            ]
        )
    ]
)
