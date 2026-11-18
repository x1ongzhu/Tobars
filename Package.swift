// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tobars",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tobars", targets: ["Tobars"]),
        .library(name: "TobarsCore", targets: ["TobarsCore"])
    ],
    targets: [
        .target(
            name: "TobarsCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Tobars",
            dependencies: ["TobarsCore"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TobarsCoreTests",
            dependencies: ["TobarsCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
