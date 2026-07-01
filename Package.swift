// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AvestaCode",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AvestaCode", targets: ["AvestaCode"]),
        .library(name: "AvestaCore", targets: ["AvestaCore"]),
        .library(name: "AvestaTerminal", targets: ["AvestaTerminal"]),
        .library(name: "AvestaUI", targets: ["AvestaUI"]),
        .library(name: "AvestaNotifications", targets: ["AvestaNotifications"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.26.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.12.0"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.10.0"),
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", branch: "with-generated-files")
    ],
    targets: [
        .executableTarget(
            name: "AvestaCode",
            dependencies: [
                "AvestaUI",
                "AvestaNotifications",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ],
            path: "App",
            exclude: ["Info.plist", "Assets.xcassets"]
        ),
        .target(
            name: "AvestaCore",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .binaryTarget(name: "GhosttyKit", path: "GhosttyKit.xcframework"),
        .target(
            name: "AvestaTerminal",
            dependencies: ["AvestaCore", "GhosttyKit"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("GameController"),
                .linkedLibrary("c++")
            ]
        ),
        .target(
            name: "AvestaUI",
            dependencies: [
                "AvestaCore",
                "AvestaTerminal",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift")
            ]
        ),
        .target(
            name: "AvestaNotifications",
            dependencies: ["AvestaCore", "AvestaTerminal"]
        ),
        .testTarget(
            name: "AvestaCoreTests",
            dependencies: [
                "AvestaCore",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            exclude: ["__Snapshots__"]
        ),
        .testTarget(
            name: "AvestaNotificationsTests",
            dependencies: ["AvestaNotifications"]
        ),
        .testTarget(
            name: "AvestaUITests",
            dependencies: [
                "AvestaUI",
                "AvestaCore",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            exclude: ["__Snapshots__", "README.md"]
        ),
        .testTarget(
            name: "AvestaTerminalTests",
            dependencies: ["AvestaTerminal"]
        )
    ]
)
