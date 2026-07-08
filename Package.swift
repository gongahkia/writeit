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
        .executable(
            name: "cerberus-wake-samples",
            targets: ["WakeSampleCapture"]
        ),
        .executable(
            name: "cerberus-wake-train",
            targets: ["WakeModelTrain"]
        ),
        .executable(
            name: "cerberus-speech-benchmark",
            targets: ["SpeechBenchmark"]
        ),
        .executable(
            name: "cerberus-model-benchmark",
            targets: ["ModelBenchmark"]
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
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreML"),
                .linkedFramework("CoreMotion"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("ImageIO"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Security"),
                .linkedFramework("SoundAnalysis"),
                .linkedFramework("Speech"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("UserNotifications"),
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
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreML"),
                .linkedFramework("CoreMotion"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("ImageIO"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Security"),
                .linkedFramework("SoundAnalysis"),
                .linkedFramework("Speech"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Vision")
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
        .executableTarget(
            name: "WakeSampleCapture",
            dependencies: ["cerberusCore"],
            path: "Sources/WakeSampleCapture",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation")
            ]
        ),
        .executableTarget(
            name: "WakeModelTrain",
            dependencies: ["cerberusCore"],
            path: "Sources/WakeModelTrain",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ],
            linkerSettings: [
                .linkedFramework("CreateML")
            ]
        ),
        .executableTarget(
            name: "SpeechBenchmark",
            dependencies: ["cerberusCore"],
            path: "Sources/SpeechBenchmark",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech")
            ]
        ),
        .executableTarget(
            name: "ModelBenchmark",
            dependencies: ["cerberusCore"],
            path: "Sources/ModelBenchmark",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ],
            linkerSettings: [
                .linkedFramework("FoundationModels")
            ]
        ),
        .testTarget(
            name: "cerberusCoreTests",
            dependencies: ["cerberusCore"],
            path: "Tests/cerberusCoreTests"
        ),
        .testTarget(
            name: "cerberusAppTests",
            dependencies: ["cerberusApp", "cerberusCore"],
            path: "Tests/cerberusAppTests"
        )
    ]
)
