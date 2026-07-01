// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "result-builder-stack-overflow-html",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/swift-foundations/swift-html-render.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "result-builder-stack-overflow-html",
            dependencies: [
                .product(name: "HTML Render", package: "swift-html-render"),
            ]
        )
    ]
)
