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
            name: "Render Primitive",
            targets: ["Render Primitive"]
        ),

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
            name: "Render Primitive",
            dependencies: []
        ),

        .target(
            name: "Render",
            dependencies: [
                "Render Primitive"
            ]
        ),
        .target(
            name: "Render Test Support",
            dependencies: [
                "Render"
            ],
            path: "Tests/Support"
        ),
        .testTarget(
            name: "Render Tests",
            dependencies: [
                "Render",
                "Render Test Support",
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
