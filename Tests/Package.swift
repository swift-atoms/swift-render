// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "testing",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/swift-foundations/swift-testing.git", branch: "main"),
    ],
    targets: [
        .testTarget(
            name: "Render Primitives Performance Tests",
            dependencies: [
                .product(name: "Render Primitives", package: "swift-render-primitives"),
                .product(name: "Render Primitives Test Support", package: "swift-render-primitives"),
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Render Primitives Performance Tests"
        ),
        .testTarget(
            name: "Render Primitives Snapshot Tests",
            dependencies: [
                .product(name: "Render Primitives", package: "swift-render-primitives"),
                .product(name: "Render Primitives Test Support", package: "swift-render-primitives"),
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Render Primitives Snapshot Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    ]
    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem
}
