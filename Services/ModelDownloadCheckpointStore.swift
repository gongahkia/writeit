import Foundation

enum ModelDownloadCheckpointError: LocalizedError, Equatable {
  case invalidCheckpoint
  case persistenceFailed

  var errorDescription: String? {
    switch self {
    case .invalidCheckpoint: "Saved model download state is invalid."
    case .persistenceFailed: "WriteIt could not save model download progress."
    }
  }
}

struct ModelDownloadCheckpoint: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let manifest: ModelManifest
  let progress: Double
  let resumeData: Data?
}

struct ModelDownloadCheckpointStore {
  private let fileURL: URL

  init(fileURL: URL) {
    self.fileURL = fileURL
  }

  func load() throws -> [ModelDownloadCheckpoint] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    let checkpoints: [ModelDownloadCheckpoint]
    do {
      checkpoints = try JSONDecoder().decode([ModelDownloadCheckpoint].self, from: Data(contentsOf: fileURL))
    } catch {
      throw ModelDownloadCheckpointError.invalidCheckpoint
    }
    guard isValid(checkpoints) else { throw ModelDownloadCheckpointError.invalidCheckpoint }
    return checkpoints.sorted { checkpointKey($0.manifest) < checkpointKey($1.manifest) }
  }

  func save(_ checkpoints: [ModelDownloadCheckpoint]) throws {
    guard isValid(checkpoints) else { throw ModelDownloadCheckpointError.invalidCheckpoint }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(checkpoints.sorted {
        checkpointKey($0.manifest) < checkpointKey($1.manifest)
      }).write(to: fileURL, options: .atomic)
    } catch let error as ModelDownloadCheckpointError {
      throw error
    } catch {
      throw ModelDownloadCheckpointError.persistenceFailed
    }
  }

  private func isValid(_ checkpoints: [ModelDownloadCheckpoint]) -> Bool {
    let keys = checkpoints.map { checkpointKey($0.manifest) }
    return Set(keys).count == keys.count
      && checkpoints.allSatisfy {
        $0.schemaVersion == ModelDownloadCheckpoint.currentSchemaVersion
          && (0...1).contains($0.progress)
      }
  }

  private func checkpointKey(_ manifest: ModelManifest) -> String {
    "\(manifest.id)@\(manifest.version)"
  }
}
