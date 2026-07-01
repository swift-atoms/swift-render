// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "cooperative-pool-stack-overflow",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "cooperative-pool-stack-overflow",
            path: "Sources",
            exclude: ["iterative-render-queue"]
        ),
        .executableTarget(
            name: "iterative-render-queue",
            path: "Sources/iterative-render-queue"
        ),
    ]
)
