// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-render-primitives",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        // MARK: - Namespace
        .library(
            name: "Render Primitive",
            targets: ["Render Primitive"]
        ),
        // MARK: - Umbrella
        .library(
            name: "Render Primitives",
            targets: ["Render Primitives"]
        ),
        .library(
            name: "Render Primitives Test Support",
            targets: ["Render Primitives Test Support"]
        ),
    ],
    dependencies: [
    ],
    targets: [
        // MARK: - Namespace
        .target(
            name: "Render Primitive",
            dependencies: []
        ),

        // MARK: - Umbrella
        .target(
            name: "Render Primitives",
            dependencies: [
                "Render Primitive",
            ]
        ),
        .target(
            name: "Render Primitives Test Support",
            dependencies: [
                "Render Primitives",
            ],
            path: "Tests/Support"
        ),
        .testTarget(
            name: "Render Primitives Tests",
            dependencies: [
                "Render Primitives",
                "Render Primitives Test Support",
            ],
            path: "Tests/Render Primitives Tests"
        )
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
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
