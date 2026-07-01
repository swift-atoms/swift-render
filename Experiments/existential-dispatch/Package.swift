// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "existential-dispatch-experiment",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Experiment",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
