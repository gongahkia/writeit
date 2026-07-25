// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "WriteIt",
  platforms: [.macOS(.v15)],
  products: [.executable(name: "WriteIt", targets: ["WriteIt"])],
  targets: [
    .executableTarget(
      name: "WriteIt",
      path: ".",
      exclude: [
        "Tests", "script", ".codex", ".github", "dist", "release", "Packaging", ".gitignore",
        "Package.swift", "README.md", "BUILD.md", "PrivacyInfo.xcprivacy",
      ],
      sources: ["App", "Models", "Services", "Views", "Support"]
    ),
    .testTarget(name: "WriteItTests", dependencies: ["WriteIt"], path: "Tests/WriteItTests"),
  ],
  swiftLanguageModes: [.v6]
)
