// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "KoraIDVExample",
    platforms: [
        .iOS(.v15)
    ],
    dependencies: [
        .package(path: "../"),
    ],
    targets: [
        .executableTarget(
            name: "KoraIDVExample",
            dependencies: [
                .product(name: "KoraIDV", package: "KoraIDV"),
            ],
            path: "KoraIDVExample"
        ),
    ]
)
