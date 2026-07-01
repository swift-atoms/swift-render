// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "body-getter-stack-overflow",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "body-getter-stack-overflow",
            path: "Sources"
        ),
    ]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableExperimentalFeature("UnderscoreOwned"),
    ]

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem
}
