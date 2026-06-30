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
    targets: [
        .executableTarget(
            name: "AvestaCode",
            dependencies: ["AvestaUI", "AvestaNotifications"],
            path: "App",
            exclude: ["Info.plist"]
        ),
        .target(name: "AvestaCore"),
        .target(
            name: "AvestaTerminal",
            dependencies: ["AvestaCore"]
        ),
        .target(
            name: "AvestaUI",
            dependencies: ["AvestaCore", "AvestaTerminal", "AvestaNotifications"]
        ),
        .target(
            name: "AvestaNotifications",
            dependencies: ["AvestaCore", "AvestaTerminal"]
        ),
        .testTarget(
            name: "AvestaCoreTests",
            dependencies: ["AvestaCore"]
        )
    ]
)
