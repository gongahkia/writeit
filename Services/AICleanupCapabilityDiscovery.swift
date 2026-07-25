import Foundation

struct AICleanupHTTPResponse: Sendable {
  let data: Data
  let statusCode: Int
}

protocol AICleanupRequesting: Sendable {
  func data(for request: URLRequest) async throws -> AICleanupHTTPResponse
}

struct AICleanupURLSession: AICleanupRequesting {
  func data(for request: URLRequest) async throws -> AICleanupHTTPResponse {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    return AICleanupHTTPResponse(data: data, statusCode: response.statusCode)
  }
}

enum AICleanupConnectionStatus: Equatable {
  case ready(models: [String], selectedModelAvailable: Bool)
  case invalidCredentials
  case notConfigured
  case unavailable
  case cancelled

  var message: String {
    switch self {
    case .ready(_, true): "Connected. Configured model is available."
    case .ready: "Connected. Configured model was not listed."
    case .invalidCredentials: "AI endpoint rejected the API key."
    case .notConfigured: "Set a chat completions URL, model, and API key first."
    case .unavailable: "AI endpoint capability discovery failed."
    case .cancelled: "AI endpoint test was cancelled."
    }
  }
}

struct AICleanupCapabilityDiscovery {
  private let requester: any AICleanupRequesting

  init(requester: any AICleanupRequesting = AICleanupURLSession()) {
    self.requester = requester
  }

  func discover(endpoint: String, apiKey: String, model: String) async -> AICleanupConnectionStatus {
    guard let url = Self.modelsURL(for: endpoint),
      model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
      apiKey.isEmpty == false
    else { return .notConfigured }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    do {
      let response = try await requester.data(for: request)
      if [401, 403].contains(response.statusCode) { return .invalidCredentials }
      guard (200...299).contains(response.statusCode),
        let payload = try? JSONDecoder().decode(ModelsResponse.self, from: response.data)
      else { return .unavailable }
      let models = payload.data.map(\.id).sorted()
      return .ready(models: models, selectedModelAvailable: models.contains(model))
    } catch is CancellationError {
      return .cancelled
    } catch {
      return .unavailable
    }
  }

  static func modelsURL(for endpoint: String) -> URL? {
    guard var components = URLComponents(string: endpoint),
      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
      components.host?.isEmpty == false,
      components.path.hasSuffix("/chat/completions")
    else { return nil }
    components.path = String(components.path.dropLast("chat/completions".count)) + "models"
    components.query = nil
    components.fragment = nil
    return components.url
  }

  private struct ModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
  }
}
