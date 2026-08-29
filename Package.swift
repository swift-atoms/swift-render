// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-render",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [

        .library(
            name: "Render",
            targets: ["Render"]
        ),
        .library(
            name: "Render Test Support",
            targets: ["Render Test Support"]
        ),
    ],
    dependencies: [],
    targets: [

        .target(
            name: "Render",
            dependencies: []
        ),
        .target(
            name: "Render Test Support",
            dependencies: [
                .target(name: "Render")
            ],
            path: "Tests/Render Test Support"
        ),
        .testTarget(
            name: "Render Tests",
            dependencies: [
                .target(name: "Render"),
                .target(name: "Render Test Support"),
            ],
            path: "Tests/Render Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("Lifetimes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
