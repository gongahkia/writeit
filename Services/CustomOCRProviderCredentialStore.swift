import Foundation

enum CustomOCRProviderCredentialError: LocalizedError, Equatable {
  case invalidBearerToken
  case authenticationNotRequired

  var errorDescription: String? {
    switch self {
    case .invalidBearerToken: "A bearer token is required."
    case .authenticationNotRequired: "This custom OCR provider does not use a bearer token."
    }
  }
}

@MainActor
protocol CustomOCRProviderCredentialStoring: AnyObject {
  func data(for account: String) throws -> Data?
  func set(_ data: Data, for account: String) throws
  func delete(_ account: String) throws
}

@MainActor
final class KeychainCustomOCRProviderCredentialStore: CustomOCRProviderCredentialStoring {
  func data(for account: String) throws -> Data? { try KeychainStore.data(for: account) }
  func set(_ data: Data, for account: String) throws { try KeychainStore.set(data, for: account) }
  func delete(_ account: String) throws { try KeychainStore.delete(account) }
}

@MainActor
final class CustomOCRProviderCredentialStore {
  private let credentials: any CustomOCRProviderCredentialStoring

  init(credentials: any CustomOCRProviderCredentialStoring = KeychainCustomOCRProviderCredentialStore()) {
    self.credentials = credentials
  }

  func saveBearerToken(_ token: String, for configuration: CustomOCRProviderConfiguration) throws {
    let configuration = try configuration.validated()
    guard configuration.authentication == .bearerToken else {
      throw CustomOCRProviderCredentialError.authenticationNotRequired
    }
    let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard token.isEmpty == false else { throw CustomOCRProviderCredentialError.invalidBearerToken }
    try credentials.set(Data(token.utf8), for: account(for: configuration))
  }

  func bearerToken(for configuration: CustomOCRProviderConfiguration) throws -> String? {
    let configuration = try configuration.validated()
    guard configuration.authentication == .bearerToken,
      let data = try credentials.data(for: account(for: configuration)),
      let token = String(data: data, encoding: .utf8), token.isEmpty == false
    else { return nil }
    return token
  }

  func replace(
    _ configuration: CustomOCRProviderConfiguration,
    previous: CustomOCRProviderConfiguration?
  ) throws {
    let configuration = try configuration.validated()
    if let previous, previous.authentication == .bearerToken,
      previous.id != configuration.id || configuration.authentication != .bearerToken
    {
      try credentials.delete(account(for: previous))
    }
  }

  func remove(_ configuration: CustomOCRProviderConfiguration) throws {
    let configuration = try configuration.validated()
    guard configuration.authentication == .bearerToken else { return }
    try credentials.delete(account(for: configuration))
  }

  func account(for configuration: CustomOCRProviderConfiguration) -> String {
    "ocr-provider.\(configuration.id).bearer-token"
  }
}
