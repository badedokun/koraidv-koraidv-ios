// swift-tools-version:5.7
//
// **Broken as of KoraIDV v1.9.0** — the parent SDK dropped its SPM
// library product when document detection moved to Google ML Kit
// (CocoaPods-only). This Example app needs to be converted to a
// CocoaPods-backed xcodeproj. Until then, demo against v1.8.5 by
// checking out the `v1.8.5` tag of koraidv-koraidv-ios and using
// `swift run KoraIDVExample`.

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
