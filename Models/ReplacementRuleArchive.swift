import Foundation

enum ReplacementRuleArchiveError: LocalizedError, Equatable {
  case unsupportedVersion
  case invalidArchive
  case unreadableFile
  case unwritableFile

  var errorDescription: String? {
    switch self {
    case .unsupportedVersion: "Replacement-rule file uses an unsupported version."
    case .invalidArchive: "Replacement-rule file is invalid."
    case .unreadableFile: "Replacement-rule file could not be read."
    case .unwritableFile: "Replacement-rule file could not be saved."
    }
  }
}

struct ReplacementRuleArchive: Codable, Sendable, Equatable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let literalRules: LiteralReplacementRules
  let regexRules: RegexReplacementRules

  init(
    literalRules: LiteralReplacementRules,
    regexRules: RegexReplacementRules
  ) {
    schemaVersion = Self.currentSchemaVersion
    self.literalRules = literalRules
    self.regexRules = regexRules
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard Set(container.allKeys).isSubset(of: Set(CodingKeys.allCases))
    else { throw ReplacementRuleArchiveError.invalidArchive }
    let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    guard schemaVersion == Self.currentSchemaVersion
    else { throw ReplacementRuleArchiveError.unsupportedVersion }
    self.schemaVersion = schemaVersion
    literalRules = try container.decode(LiteralReplacementRules.self, forKey: .literalRules)
    regexRules = try container.decode(RegexReplacementRules.self, forKey: .regexRules)
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion
    case literalRules
    case regexRules
  }
}

enum ReplacementRuleArchiveCodec {
  static func encode(_ archive: ReplacementRuleArchive) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(archive)
  }

  static func decode(_ data: Data) throws -> ReplacementRuleArchive {
    do {
      return try JSONDecoder().decode(ReplacementRuleArchive.self, from: data)
    } catch let error as ReplacementRuleArchiveError {
      throw error
    } catch {
      throw ReplacementRuleArchiveError.invalidArchive
    }
  }
}

enum ReplacementRuleArchiveFileStore {
  static func read(from url: URL) throws -> Data {
    do {
      return try Data(contentsOf: url)
    } catch {
      throw ReplacementRuleArchiveError.unreadableFile
    }
  }

  static func write(_ data: Data, to url: URL) throws {
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      throw ReplacementRuleArchiveError.unwritableFile
    }
  }
}
