// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "WriteIt",
  platforms: [.macOS(.v15)],
  products: [.executable(name: "WriteIt", targets: ["WriteIt"])],
  targets: [
    .executableTarget(
      name: "WriteIt",
      path: ".",
      exclude: ["Tests", "script", ".codex", ".gitignore", "Package.swift"],
      sources: ["App", "Models", "Services", "Views", "Support"]
    ),
    .testTarget(name: "WriteItTests", dependencies: ["WriteIt"], path: "Tests/WriteItTests")
  ]
)
