// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PromptImproverCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PromptImproverCore", targets: ["PromptImproverCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.8.0")
    ],
    targets: [
        .target(
            name: "PromptImproverCore",
            path: "PromptImprover",
            exclude: [
                "App",
                "UI",
                "Assets.xcassets",
                "Resources",
                "PromptImproverApp.swift"
            ],
            sources: [
                "CLI",
                "Core",
                "Execution",
                "Providers",
                "Workspace"
            ]
        ),
        .testTarget(
            name: "PromptImproverCoreTests",
            dependencies: [
                "PromptImproverCore",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/Unit",
            resources: [
                .copy("../Fixtures")
            ]
        )
    ]
)
