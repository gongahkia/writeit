// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "cerberus",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "cerberus",
            targets: ["cerberusApp"]
        ),
        .library(
            name: "CerberusCore",
            targets: ["cerberusCore"]
        )
    ],
    targets: [
        .executableTarget(
            name: "cerberusApp",
            dependencies: ["cerberusCore"],
            path: "Sources/cerberusApp",
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMotion"),
                .linkedFramework("EventKit"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("Security"),
                .linkedFramework("Speech"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .target(
            name: "cerberusCore",
            path: "Sources/cerberusCore",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMotion"),
                .linkedFramework("EventKit"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("Security"),
                .linkedFramework("Speech")
            ]
        ),
        .testTarget(
            name: "cerberusCoreTests",
            dependencies: ["cerberusCore"],
            path: "Tests/cerberusCoreTests"
        )
    ]
)
