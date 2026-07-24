import Foundation

enum GitHubReleaseManifestError: LocalizedError, Equatable {
  case invalidRepository
  case networkUnavailable
  case releaseUnavailable
  case releaseResponseInvalid
  case manifestAssetUnavailable
  case manifestResponseInvalid
  case unsupportedManifestSchema
  case invalidManifestContent

  var errorDescription: String? {
    switch self {
    case .invalidRepository: "The configured model repository is invalid."
    case .networkUnavailable: "WriteIt could not reach the model release."
    case .releaseUnavailable: "No published model release is available."
    case .releaseResponseInvalid: "The model release response was invalid."
    case .manifestAssetUnavailable: "The model release did not include its manifest."
    case .manifestResponseInvalid: "The model manifest could not be read."
    case .unsupportedManifestSchema: "The model manifest format is not supported."
    case .invalidManifestContent: "The model manifest contains invalid model metadata."
    }
  }
}

struct GitHubReleaseRepository: Equatable, Sendable {
  let owner: String
  let name: String

  init(owner: String, name: String) throws {
    guard Self.isSafeComponent(owner), Self.isSafeComponent(name) else {
      throw GitHubReleaseManifestError.invalidRepository
    }
    self.owner = owner
    self.name = name
  }

  var latestReleaseURL: URL {
    URL(string: "https://api.github.com")!
      .appendingPathComponent("repos")
      .appendingPathComponent(owner)
      .appendingPathComponent(name)
      .appendingPathComponent("releases")
      .appendingPathComponent("latest")
  }

  private static func isSafeComponent(_ value: String) -> Bool {
    !value.isEmpty && !value.contains("/") && !value.contains("\\")
  }
}

struct VersionedModelManifest: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let models: [ModelManifest]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case models
  }

  func validated() throws -> Self {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw GitHubReleaseManifestError.unsupportedManifestSchema
    }
    let identities = models.map { "\($0.id)@\($0.version)" }
    guard Set(identities).count == identities.count,
      models.allSatisfy(Self.isValid)
    else {
      throw GitHubReleaseManifestError.invalidManifestContent
    }
    return self
  }

  private static func isValid(_ manifest: ModelManifest) -> Bool {
    let hash = manifest.sha256.lowercased()
    return isSafeComponent(manifest.id)
      && isSafeComponent(manifest.version)
      && manifest.downloadURL.scheme?.lowercased() == "https"
      && manifest.downloadURL.host != nil
      && hash.count == 64
      && hash.allSatisfy { $0.isASCII && $0.isHexDigit }
      && !manifest.license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !manifest.supportedLanguages.isEmpty
  }

  private static func isSafeComponent(_ value: String) -> Bool {
    !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
  }
}

struct GitHubReleaseHTTPResponse: Sendable {
  let data: Data
  let statusCode: Int
}

protocol GitHubReleaseRequesting: Sendable {
  func data(for request: URLRequest) async throws -> GitHubReleaseHTTPResponse
}

struct URLSessionGitHubReleaseRequester: GitHubReleaseRequesting {
  func data(for request: URLRequest) async throws -> GitHubReleaseHTTPResponse {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw GitHubReleaseManifestError.networkUnavailable
    }
    return GitHubReleaseHTTPResponse(data: data, statusCode: response.statusCode)
  }
}

struct GitHubReleaseManifestFetcher: Sendable {
  static let defaultManifestAssetName = "writeit-model-manifest.json"

  private let repository: GitHubReleaseRepository
  private let manifestAssetName: String
  private let requester: any GitHubReleaseRequesting

  init(
    repository: GitHubReleaseRepository,
    manifestAssetName: String = Self.defaultManifestAssetName,
    requester: any GitHubReleaseRequesting = URLSessionGitHubReleaseRequester()
  ) {
    self.repository = repository
    self.manifestAssetName = manifestAssetName
    self.requester = requester
  }

  func fetch() async throws -> VersionedModelManifest {
    let releaseData = try await requestReleaseData(at: repository.latestReleaseURL, releaseRequest: true)
    let release: GitHubRelease
    do {
      release = try JSONDecoder().decode(GitHubRelease.self, from: releaseData)
    } catch {
      throw GitHubReleaseManifestError.releaseResponseInvalid
    }
    guard !release.draft, !release.prerelease else {
      throw GitHubReleaseManifestError.releaseUnavailable
    }
    let assets = release.assets.filter { $0.name == manifestAssetName }
    guard assets.count == 1, let manifestURL = assets.first?.browserDownloadURL,
      manifestURL.scheme?.lowercased() == "https"
    else {
      throw GitHubReleaseManifestError.manifestAssetUnavailable
    }
    let manifestData = try await requestReleaseData(at: manifestURL, releaseRequest: false)
    let manifest: VersionedModelManifest
    do {
      manifest = try JSONDecoder().decode(VersionedModelManifest.self, from: manifestData)
    } catch {
      throw GitHubReleaseManifestError.manifestResponseInvalid
    }
    return try manifest.validated()
  }

  private func requestReleaseData(at url: URL, releaseRequest: Bool) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue("WriteIt", forHTTPHeaderField: "User-Agent")
    if releaseRequest {
      request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
      request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
    }
    let response: GitHubReleaseHTTPResponse
    do {
      response = try await requester.data(for: request)
    } catch let error as GitHubReleaseManifestError {
      throw error
    } catch {
      throw GitHubReleaseManifestError.networkUnavailable
    }
    guard (200...299).contains(response.statusCode) else {
      throw releaseRequest
        ? GitHubReleaseManifestError.releaseUnavailable
        : GitHubReleaseManifestError.manifestAssetUnavailable
    }
    return response.data
  }
}

private struct GitHubRelease: Decodable {
  let draft: Bool
  let prerelease: Bool
  let assets: [GitHubReleaseAsset]
}

private struct GitHubReleaseAsset: Decodable {
  let name: String
  let browserDownloadURL: URL

  enum CodingKeys: String, CodingKey {
    case name
    case browserDownloadURL = "browser_download_url"
  }
}
