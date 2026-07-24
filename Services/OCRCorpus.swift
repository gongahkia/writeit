import Foundation

struct OCRCorpusManifest: Codable, Equatable {
  static let currentVersion = 1

  let version: Int
  let entries: [OCRCorpusEntry]
}

struct OCRCorpusEntry: Codable, Equatable, Identifiable {
  let id: String
  let imagePath: String
  let transcription: String
  let language: RecognitionLanguage
}

struct OCRCorpusFixture: Equatable {
  let entry: OCRCorpusEntry
  let imageData: Data
}

enum OCRCorpusError: Error, Equatable {
  case unsupportedVersion
  case duplicateIdentifier
  case invalidImagePath
  case unreadableImage
}

enum OCRCorpusFixtureLoader {
  static func load(manifestData: Data, directory: URL) throws -> [OCRCorpusFixture] {
    let manifest = try JSONDecoder().decode(OCRCorpusManifest.self, from: manifestData)
    guard manifest.version == OCRCorpusManifest.currentVersion else {
      throw OCRCorpusError.unsupportedVersion
    }
    let entries = manifest.entries.sorted { $0.id < $1.id }
    guard Set(entries.map(\.id)).count == entries.count else {
      throw OCRCorpusError.duplicateIdentifier
    }
    return try entries.map { entry in
      guard isRelativeImagePath(entry.imagePath) else { throw OCRCorpusError.invalidImagePath }
      let imageURL = directory.appendingPathComponent(entry.imagePath, isDirectory: false)
      guard let imageData = try? Data(contentsOf: imageURL), imageData.isEmpty == false else {
        throw OCRCorpusError.unreadableImage
      }
      return OCRCorpusFixture(entry: entry, imageData: imageData)
    }
  }

  private static func isRelativeImagePath(_ path: String) -> Bool {
    path.isEmpty == false
      && path.hasPrefix("/") == false
      && path.split(separator: "/").contains("..") == false
  }
}
