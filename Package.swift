// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KoraIDV",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "KoraIDV",
            targets: ["KoraIDV"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "KoraIDV",
            dependencies: [],
            path: "Sources/KoraIDV",
            resources: [
                .process("UI/Localization")
            ]
        ),
        .testTarget(
            name: "KoraIDVTests",
            dependencies: ["KoraIDV"],
            path: "Tests/KoraIDVTests"
        ),
    ]
)
