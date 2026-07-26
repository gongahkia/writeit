import Combine
import Foundation

enum CustomHTTPSModelSourceError: LocalizedError, Equatable {
  case invalidURL
  case networkUnavailable
  case invalidResponse
  case invalidManifest
  case downloadFailed
  case assetTooLarge

  var errorDescription: String? {
    switch self {
    case .invalidURL: "Enter a valid public HTTPS manifest URL."
    case .networkUnavailable: "WriteIt could not reach the model source."
    case .invalidResponse: "The model source returned an invalid response."
    case .invalidManifest: "The model manifest is invalid or unsupported."
    case .downloadFailed: "WriteIt could not download the selected model."
    case .assetTooLarge: "The downloaded model size does not match its manifest."
    }
  }
}

struct CustomHTTPSModelHTTPResponse: Sendable {
  let data: Data
  let statusCode: Int
  let finalURL: URL
}

protocol CustomHTTPSModelRequesting: Sendable {
  func data(for request: URLRequest) async throws -> CustomHTTPSModelHTTPResponse
}

struct URLSessionCustomHTTPSModelRequester: CustomHTTPSModelRequesting {
  func data(for request: URLRequest) async throws -> CustomHTTPSModelHTTPResponse {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw CustomHTTPSModelSourceError.networkUnavailable }
    return CustomHTTPSModelHTTPResponse(data: data, statusCode: response.statusCode, finalURL: response.url ?? request.url!)
  }
}

struct CustomHTTPSModelManifestFetcher: Sendable {
  private let requester: any CustomHTTPSModelRequesting

  init(requester: any CustomHTTPSModelRequesting = URLSessionCustomHTTPSModelRequester()) {
    self.requester = requester
  }

  func fetch(at url: URL) async throws -> VersionedModelManifest {
    try validateHTTPS(url)
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("WriteIt", forHTTPHeaderField: "User-Agent")
    let response: CustomHTTPSModelHTTPResponse
    do {
      response = try await requester.data(for: request)
    } catch let error as CustomHTTPSModelSourceError {
      throw error
    } catch {
      throw CustomHTTPSModelSourceError.networkUnavailable
    }
    guard (200...299).contains(response.statusCode) else { throw CustomHTTPSModelSourceError.invalidResponse }
    try validateHTTPS(response.finalURL)
    do {
      return try JSONDecoder().decode(VersionedModelManifest.self, from: response.data).validated()
    } catch {
      throw CustomHTTPSModelSourceError.invalidManifest
    }
  }

  private func validateHTTPS(_ url: URL) throws {
    guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
      throw CustomHTTPSModelSourceError.invalidURL
    }
  }
}

struct CustomHTTPSModelAssetDownloader: Sendable {
  func download(_ manifest: ModelManifest) async throws -> URL {
    guard manifest.downloadURL.scheme?.lowercased() == "https", manifest.downloadURL.host?.isEmpty == false else {
      throw CustomHTTPSModelSourceError.invalidManifest
    }
    do {
      let (url, response) = try await URLSession.shared.download(from: manifest.downloadURL)
      guard let response = response as? HTTPURLResponse,
        (200...299).contains(response.statusCode), response.url?.scheme?.lowercased() == "https"
      else { throw CustomHTTPSModelSourceError.downloadFailed }
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
      guard size == manifest.assetSizeBytes else { throw CustomHTTPSModelSourceError.assetTooLarge }
      return url
    } catch let error as CustomHTTPSModelSourceError {
      throw error
    } catch {
      throw CustomHTTPSModelSourceError.downloadFailed
    }
  }
}

@MainActor
final class CustomHTTPSModelSourceStore: ObservableObject {
  @Published private(set) var manifestURL: String
  @Published private(set) var manifest: VersionedModelManifest?
  @Published private(set) var message: String?
  @Published private(set) var isLoading = false

  private static let manifestURLDefaultsKey = "models.customHTTPSManifestURL"
  private let defaults: UserDefaults
  private let fetcher: CustomHTTPSModelManifestFetcher
  private let downloader: CustomHTTPSModelAssetDownloader

  init(
    defaults: UserDefaults = .standard,
    fetcher: CustomHTTPSModelManifestFetcher = CustomHTTPSModelManifestFetcher(),
    downloader: CustomHTTPSModelAssetDownloader = CustomHTTPSModelAssetDownloader()
  ) {
    self.defaults = defaults
    self.fetcher = fetcher
    self.downloader = downloader
    manifestURL = defaults.string(forKey: Self.manifestURLDefaultsKey) ?? ""
  }

  var models: [ModelManifest] { manifest?.models ?? [] }

  func setManifestURL(_ value: String) {
    manifestURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
    defaults.set(manifestURL, forKey: Self.manifestURLDefaultsKey)
    manifest = nil
    message = nil
  }

  func refresh() async {
    guard let url = URL(string: manifestURL) else {
      message = CustomHTTPSModelSourceError.invalidURL.errorDescription
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let loaded = try await fetcher.fetch(at: url)
      manifest = loaded
      message = "Loaded \(loaded.models.count) compatible manifest entries."
    } catch {
      manifest = nil
      message = (error as? LocalizedError)?.errorDescription ?? CustomHTTPSModelSourceError.networkUnavailable.errorDescription
    }
  }

  func download(_ manifest: ModelManifest, into models: ModelStore) async {
    models.recordDownloadProgress(for: manifest, progress: 0.05, resumeData: nil)
    do {
      let temporaryURL = try await downloader.download(manifest)
      defer { try? FileManager.default.removeItem(at: temporaryURL) }
      models.recordDownloadProgress(for: manifest, progress: 0.9, resumeData: nil)
      models.install(manifest: manifest, stagedAssetURL: temporaryURL)
      message = models.error == nil ? "Installed \(manifest.id) \(manifest.version)." : models.error?.message
    } catch {
      models.pauseDownload(for: manifest, resumeData: nil)
      message = (error as? LocalizedError)?.errorDescription ?? CustomHTTPSModelSourceError.downloadFailed.errorDescription
    }
  }
}
