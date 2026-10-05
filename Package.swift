// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "swift-cyclomatic-complexity-plugin",
    platforms: [.macOS(.v27)],
    products: [
        .library(
            name: "CyclomaticComplexity",
            targets: ["CyclomaticComplexity"]
        ),
        .executable(name: "swift-complexity", targets: ["swift-complexity"]),
        .plugin(
            name: "CyclomaticComplexityBuildPlugin",
            targets: ["CyclomaticComplexityBuildPlugin"]
        ),
        .plugin(
            name: "CyclomaticComplexityCommandPlugin",
            targets: ["CyclomaticComplexityCommandPlugin"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            from: "604.0.0"
        ),
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.8.2"
        ),
    ],
    targets: [
        .target(
            name: "CyclomaticComplexity",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(
                    name: "SwiftParserDiagnostics",
                    package: "swift-syntax"
                ),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "swift-complexity",
            dependencies: [
                "CyclomaticComplexity",
                .product(
                    name: "ArgumentParser",
                    package: "swift-argument-parser"
                ),
            ]
        ),
        .plugin(
            name: "CyclomaticComplexityBuildPlugin",
            capability: .buildTool(),
            dependencies: ["swift-complexity"]
        ),
        .plugin(
            name: "CyclomaticComplexityCommandPlugin",
            capability: .command(
                intent: .custom(
                    verb: "complexity",
                    description: "Measure Swift 6.4 cyclomatic complexity"
                )
            ),
            dependencies: ["swift-complexity"]
        ),
        .testTarget(
            name: "CyclomaticComplexityTests",
            dependencies: ["CyclomaticComplexity"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "PluginIntegrationTests", dependencies: []),
    ]
)
