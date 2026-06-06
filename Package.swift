// swift-tools-version:5.7
//
// **v1.9.0: KoraIDV no longer ships a Swift Package Manager library
// product.** Document detection now depends on Google ML Kit, which
// Google distributes via CocoaPods only — there is no Google-owned SPM
// distribution of the ML Kit standalone iOS SDK. Rather than depend on
// a third-party SPM shim around the ML Kit XCFrameworks, the SDK is
// CocoaPods-only as of v1.9.0. SPM consumers should pin to v1.8.5 or
// migrate to CocoaPods. See README.md for installation instructions.
//
// This Package.swift is retained so `swift test` keeps working for
// internal unit tests against non-MLKit code. The two files that import
// ML Kit (`Capture/DocumentScanner.swift` and the camera-view caller
// `UI/Views/DocumentCaptureView.swift`) are excluded from the SPM
// target. The `.library` product is intentionally absent — consuming
// this repo as an SPM package will fail at resolve time with a clear
// "no library products" error, which is the explicit signal we want.

import PackageDescription

let package = Package(
    name: "KoraIDV",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        // No library product — see header comment. CocoaPods only.
    ],
    dependencies: [],
    targets: [
        .target(
            name: "KoraIDV",
            dependencies: [],
            path: "Sources/KoraIDV",
            exclude: [
                "Capture/DocumentScanner.swift",
                "UI/Views/DocumentCaptureView.swift",
            ],
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
