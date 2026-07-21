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
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.10.0"),
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", branch: "with-generated-files")
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .executableTarget(
            name: "AvestaCode",
            dependencies: [
                "AvestaUI",
                "AvestaNotifications",
                "AvestaTerminal"
            ],
            path: "App",
            exclude: ["Info.plist", "AvestaCode.entitlements", "Assets.xcassets", "BUILD.bazel"]
        ),
        .target(
            name: "AvestaCore",
            dependencies: ["CSQLite"],
            exclude: ["BUILD.bazel"],
            linkerSettings: [.linkedLibrary("sqlite3"), .linkedLibrary("compression")]
        ),
        .binaryTarget(name: "GhosttyKit", path: "GhosttyKit.xcframework"),
        .target(
            name: "AvestaTerminal",
            dependencies: ["AvestaCore", "GhosttyKit"],
            exclude: ["BUILD.bazel"],
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
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift")
            ],
            exclude: ["BUILD.bazel"]
        ),
        .target(name: "AvestaNotifications", dependencies: ["AvestaCore", "AvestaTerminal"], exclude: ["BUILD.bazel"]),
        .testTarget(
            name: "AvestaCoreTests",
            dependencies: ["AvestaCore"],
            exclude: ["__Snapshots__", "BUILD.bazel"]
        ),
        .testTarget(
            name: "AvestaNotificationsTests",
            dependencies: ["AvestaNotifications"],
            exclude: ["BUILD.bazel"]
        ),
        .testTarget(
            name: "AvestaUITests",
            dependencies: [
                "AvestaUI",
                "AvestaCore"
            ],
            exclude: ["__Snapshots__", "BUILD.bazel"]
        ),
        .testTarget(
            name: "AvestaTerminalTests",
            dependencies: ["AvestaTerminal"],
            exclude: ["BUILD.bazel"]
        )
    ]
)
