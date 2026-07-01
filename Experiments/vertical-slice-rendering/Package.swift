// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "vertical-slice-rendering",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/swift-iso/swift-iso-32000.git", branch: "main"),
        .package(url: "https://github.com/swift-whatwg/swift-whatwg-html.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "vertical-slice-rendering",
            dependencies: [
                .product(name: "ISO 32000", package: "swift-iso-32000"),
                .product(name: "WHATWG HTML Shared", package: "swift-whatwg-html"),
                .product(name: "WHATWG HTML Sections", package: "swift-whatwg-html"),
                .product(name: "WHATWG HTML Grouping", package: "swift-whatwg-html"),
                .product(name: "WHATWG HTML TextSemantics", package: "swift-whatwg-html"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableExperimentalFeature("Lifetimes"),
                .enableExperimentalFeature("SuppressedAssociatedTypes"),
            ]
        )
    ]
)
