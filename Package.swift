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
        .executable(
            name: "cerberus-adapter-eval",
            targets: ["AdapterEval"]
        ),
        .executable(
            name: "cerberus-head-gesture-eval",
            targets: ["HeadGestureEval"]
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
                .linkedFramework("AudioToolbox"),
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
                .linkedFramework("AudioToolbox"),
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
        .executableTarget(
            name: "AdapterEval",
            dependencies: ["cerberusCore"],
            path: "Sources/AdapterEval",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ],
            linkerSettings: [
                .linkedFramework("FoundationModels")
            ]
        ),
        .executableTarget(
            name: "HeadGestureEval",
            dependencies: ["cerberusCore"],
            path: "Sources/HeadGestureEval",
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
