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
        .executable(
            name: "ShellExecService",
            targets: ["ShellExecService"]
        ),
        .executable(
            name: "cerberus-adapter-dataset",
            targets: ["AdapterDatasetExport"]
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
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMotion"),
                .linkedFramework("EventKit"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("Network"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Security"),
                .linkedFramework("Speech"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Vision")
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
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMotion"),
                .linkedFramework("EventKit"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("Network"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Security"),
                .linkedFramework("Speech"),
                .linkedFramework("Vision")
            ]
        ),
        .executableTarget(
            name: "ShellExecService",
            dependencies: ["cerberusCore"],
            path: "Sources/ShellExecService",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .executableTarget(
            name: "AdapterDatasetExport",
            dependencies: ["cerberusCore"],
            path: "Sources/AdapterDatasetExport",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "cerberusCoreTests",
            dependencies: ["cerberusCore"],
            path: "Tests/cerberusCoreTests"
        )
    ]
)
