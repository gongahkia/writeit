import Foundation

enum ManifestModelInstallerError: LocalizedError, Equatable {
  case invalidManifest
  case assetMissing
  case alreadyInstalled
  case installFailed
  case removalFailed

  var errorDescription: String? {
    switch self {
    case .invalidManifest: "The model manifest has an unsafe identifier or version."
    case .assetMissing: "The staged model asset is unavailable."
    case .alreadyInstalled: "This model version is already installed."
    case .installFailed: "WriteIt could not install the selected model version."
    case .removalFailed: "WriteIt could not delete the selected model version."
    }
  }
}

private struct InstalledModelRecord: Codable {
  static let schemaVersion = 1

  let schemaVersion: Int
  let manifest: ModelManifest
  let assetName: String
}

enum ManifestModelInstaller {
  private static let recordFileName = ".writeit-model.json"

  static func installedAssetURL(for manifest: ModelManifest, in modelsDirectory: URL) -> URL? {
    guard let directory = try? installationDirectory(for: manifest, in: modelsDirectory) else {
      return nil
    }
    let recordURL = directory.appendingPathComponent(recordFileName)
    guard let record = try? JSONDecoder().decode(
      InstalledModelRecord.self, from: Data(contentsOf: recordURL)),
      record.schemaVersion == InstalledModelRecord.schemaVersion,
      record.manifest == manifest,
      isSafePathComponent(record.assetName)
    else { return nil }
    let assetURL = directory.appendingPathComponent(record.assetName, isDirectory: true)
    return FileManager.default.fileExists(atPath: assetURL.path) ? assetURL : nil
  }

  static func install(
    manifest: ModelManifest,
    stagedAssetURL: URL,
    in modelsDirectory: URL
  ) throws -> URL {
    guard FileManager.default.fileExists(atPath: stagedAssetURL.path) else {
      throw ManifestModelInstallerError.assetMissing
    }
    let destination = try installationDirectory(for: manifest, in: modelsDirectory)
    try ModelAssetDigestVerifier.verify(assetURL: stagedAssetURL, expectedSHA256: manifest.sha256)
    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw ManifestModelInstallerError.alreadyInstalled
    }
    let assetName = stagedAssetURL.lastPathComponent
    guard isSafePathComponent(assetName) else { throw ManifestModelInstallerError.assetMissing }
    let stagingDirectory = modelsDirectory.appendingPathComponent(
      ".staging-\(UUID().uuidString)", isDirectory: true)
    var moved = false
    defer {
      if !moved { try? FileManager.default.removeItem(at: stagingDirectory) }
    }
    do {
      try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
      let stagedAsset = stagingDirectory.appendingPathComponent(assetName, isDirectory: true)
      try FileManager.default.copyItem(at: stagedAssetURL, to: stagedAsset)
      let record = InstalledModelRecord(
        schemaVersion: InstalledModelRecord.schemaVersion,
        manifest: manifest,
        assetName: assetName
      )
      try JSONEncoder().encode(record).write(
        to: stagingDirectory.appendingPathComponent(recordFileName), options: .atomic)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.moveItem(at: stagingDirectory, to: destination)
      moved = true
      return destination.appendingPathComponent(assetName, isDirectory: true)
    } catch {
      throw ManifestModelInstallerError.installFailed
    }
  }

  static func remove(manifest: ModelManifest, in modelsDirectory: URL) throws {
    let destination = try installationDirectory(for: manifest, in: modelsDirectory)
    guard FileManager.default.fileExists(atPath: destination.path) else { return }
    do {
      try FileManager.default.removeItem(at: destination)
    } catch {
      throw ManifestModelInstallerError.removalFailed
    }
  }

  private static func installationDirectory(for manifest: ModelManifest, in modelsDirectory: URL) throws
    -> URL
  {
    guard isSafePathComponent(manifest.id), isSafePathComponent(manifest.version) else {
      throw ManifestModelInstallerError.invalidManifest
    }
    return modelsDirectory
      .appendingPathComponent(manifest.id, isDirectory: true)
      .appendingPathComponent(manifest.version, isDirectory: true)
  }

  private static func isSafePathComponent(_ value: String) -> Bool {
    !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
  }
}
