// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "result-builder-stack-overflow",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "result-builder-stack-overflow"
        )
    ]
)
