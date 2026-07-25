import Foundation

struct CustomOCRProviderHTTPResponse: Sendable {
  let data: Data
  let statusCode: Int
}

protocol CustomOCRProviderRequesting: Sendable {
  func data(for request: URLRequest) async throws -> CustomOCRProviderHTTPResponse
}

struct URLSessionCustomOCRProviderRequester: CustomOCRProviderRequesting {
  func data(for request: URLRequest) async throws -> CustomOCRProviderHTTPResponse {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    return CustomOCRProviderHTTPResponse(data: data, statusCode: response.statusCode)
  }
}

enum CustomOCRProviderTestStatus: Sendable, Equatable {
  case valid
  case invalidCredentials
  case notConfigured
  case invalidResponse
  case unavailable
  case cancelled
}

actor CustomOCRProviderTestService {
  private let configuration: CustomOCRProviderConfiguration
  private let bearerToken: String?
  private let requester: any CustomOCRProviderRequesting

  init(
    configuration: CustomOCRProviderConfiguration,
    bearerToken: String? = nil,
    requester: any CustomOCRProviderRequesting = URLSessionCustomOCRProviderRequester()
  ) {
    self.configuration = configuration
    self.bearerToken = bearerToken
    self.requester = requester
  }

  func testRequest() async -> CustomOCRProviderTestStatus {
    guard let configuration = try? configuration.validated() else {
      return .notConfigured
    }
    if configuration.authentication == .bearerToken,
      bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    {
      return .notConfigured
    }
    do {
      let encodedImage = try CloudImageRequestEncoder.encode(CloudCredentialValidationProbe.imageData)
      let body = try CustomOCRProviderRequest(
        imageData: encodedImage.data,
        imageContentType: encodedImage.contentType,
        language: .english
      )
      var request = URLRequest(url: configuration.endpoint)
      request.httpMethod = "POST"
      request.timeoutInterval = CloudRequestPolicy.timeoutInterval
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
      if let bearerToken, configuration.authentication == .bearerToken {
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
      }
      request.httpBody = try JSONEncoder().encode(body)
      let response = try await requester.data(for: request)
      switch response.statusCode {
      case 200...299:
        let decoded = try JSONDecoder().decode(CustomOCRProviderResponse.self, from: response.data)
        _ = try decoded.recognitionResult(provider: configuration, language: .english)
        return .valid
      case 401, 403:
        return .invalidCredentials
      default:
        return .unavailable
      }
    } catch is CancellationError {
      return .cancelled
    } catch is CustomOCRProviderContractError {
      return .invalidResponse
    } catch is DecodingError {
      return .invalidResponse
    } catch {
      return .unavailable
    }
  }
}
