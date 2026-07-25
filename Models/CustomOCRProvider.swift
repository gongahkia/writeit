import Foundation

enum CustomOCRProviderContractError: LocalizedError, Equatable {
  case unsupportedSchema
  case invalidIdentifier
  case invalidDisplayName
  case invalidEndpoint
  case noSupportedLanguages
  case invalidImage
  case invalidContentType
  case invalidText
  case invalidConfidence

  var errorDescription: String? {
    switch self {
    case .unsupportedSchema: "The custom OCR provider schema is not supported."
    case .invalidIdentifier: "The custom OCR provider identifier is invalid."
    case .invalidDisplayName: "The custom OCR provider name is invalid."
    case .invalidEndpoint: "The custom OCR provider endpoint must use HTTPS or local HTTP."
    case .noSupportedLanguages: "The custom OCR provider must support at least one language."
    case .invalidImage: "The custom OCR request must contain an image."
    case .invalidContentType: "The custom OCR image format is not supported."
    case .invalidText: "The custom OCR provider returned no usable text."
    case .invalidConfidence: "The custom OCR provider returned an invalid confidence score."
    }
  }
}

enum CustomOCRProviderAuthentication: String, Codable, Sendable, Equatable {
  case none
  case bearerToken
}

struct CustomOCRProviderConfiguration: Codable, Sendable, Equatable, Identifiable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let id: String
  let displayName: String
  let endpoint: URL
  let authentication: CustomOCRProviderAuthentication
  let supportedLanguages: Set<RecognitionLanguage>

  init(
    id: String,
    displayName: String,
    endpoint: URL,
    authentication: CustomOCRProviderAuthentication,
    supportedLanguages: Set<RecognitionLanguage>,
    schemaVersion: Int = Self.currentSchemaVersion
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.displayName = displayName
    self.endpoint = endpoint
    self.authentication = authentication
    self.supportedLanguages = supportedLanguages
  }

  func validated() throws -> Self {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw CustomOCRProviderContractError.unsupportedSchema
    }
    let suffix = id.dropFirst("custom.".count)
    guard id.hasPrefix("custom."), !suffix.isEmpty,
      suffix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" })
    else { throw CustomOCRProviderContractError.invalidIdentifier }
    guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CustomOCRProviderContractError.invalidDisplayName
    }
    guard Self.isAllowedEndpoint(endpoint) else { throw CustomOCRProviderContractError.invalidEndpoint }
    guard !supportedLanguages.isEmpty else {
      throw CustomOCRProviderContractError.noSupportedLanguages
    }
    return self
  }

  private static func isAllowedEndpoint(_ endpoint: URL) -> Bool {
    guard endpoint.user == nil, endpoint.password == nil, endpoint.query == nil,
      endpoint.fragment == nil, let scheme = endpoint.scheme?.lowercased(), let host = endpoint.host?.lowercased()
    else { return false }
    if scheme == "https" { return true }
    return scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
  }
}

struct CustomOCRProviderRequest: Codable, Sendable, Equatable {
  static let currentSchemaVersion = 1
  static let allowedImageContentTypes: Set<String> = ["image/jpeg", "image/png"]

  let schemaVersion: Int
  let imageBase64: String
  let imageContentType: String
  let language: RecognitionLanguage

  init(
    imageData: Data,
    imageContentType: String,
    language: RecognitionLanguage,
    schemaVersion: Int = Self.currentSchemaVersion
  ) throws {
    self.schemaVersion = schemaVersion
    imageBase64 = imageData.base64EncodedString()
    self.imageContentType = imageContentType
    self.language = language
    _ = try validated()
  }

  func validated() throws -> Self {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw CustomOCRProviderContractError.unsupportedSchema
    }
    guard let data = Data(base64Encoded: imageBase64), !data.isEmpty else {
      throw CustomOCRProviderContractError.invalidImage
    }
    guard Self.allowedImageContentTypes.contains(imageContentType.lowercased()) else {
      throw CustomOCRProviderContractError.invalidContentType
    }
    return self
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case imageBase64 = "image_base64"
    case imageContentType = "image_content_type"
    case language
  }
}

struct CustomOCRProviderResponse: Codable, Sendable, Equatable {
  let text: String
  let confidence: Float

  func recognitionResult(
    provider: CustomOCRProviderConfiguration,
    language: RecognitionLanguage
  ) throws -> RecognitionResult {
    _ = try provider.validated()
    let normalizedText = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
      .precomposedStringWithCanonicalMapping
    guard !normalizedText.isEmpty else { throw CustomOCRProviderContractError.invalidText }
    guard (0...1).contains(confidence) else {
      throw CustomOCRProviderContractError.invalidConfidence
    }
    guard provider.supportedLanguages.contains(language) else {
      throw RecognitionError.unavailable(
        "\(provider.displayName) does not support \(language.displayName)."
      )
    }
    return RecognitionResult(
      text: normalizedText,
      confidence: confidence,
      backendID: provider.id,
      languageResolution: .identity(language)
    )
  }
}
