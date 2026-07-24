import CryptoKit
import Foundation

enum ModelAssetDigestError: LocalizedError, Equatable {
  case assetMissing
  case assetIsNotAFile
  case assetUnreadable
  case invalidExpectedDigest
  case digestMismatch

  var errorDescription: String? {
    switch self {
    case .assetMissing: "The downloaded model asset is unavailable."
    case .assetIsNotAFile: "The downloaded model asset is not a file."
    case .assetUnreadable: "The downloaded model asset could not be read."
    case .invalidExpectedDigest: "The model manifest contains an invalid SHA-256 digest."
    case .digestMismatch: "The downloaded model asset did not match its SHA-256 digest."
    }
  }
}

enum ModelAssetDigestVerifier {
  private static let chunkSize = 1_048_576

  static func verify(assetURL: URL, expectedSHA256: String) throws {
    guard isSHA256Digest(expectedSHA256) else {
      throw ModelAssetDigestError.invalidExpectedDigest
    }
    guard try sha256(for: assetURL).caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
      throw ModelAssetDigestError.digestMismatch
    }
  }

  static func sha256(for assetURL: URL) throws -> String {
    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: assetURL.path, isDirectory: &isDirectory) else {
      throw ModelAssetDigestError.assetMissing
    }
    guard !isDirectory.boolValue else { throw ModelAssetDigestError.assetIsNotAFile }
    let file: FileHandle
    do {
      file = try FileHandle(forReadingFrom: assetURL)
    } catch {
      throw ModelAssetDigestError.assetUnreadable
    }
    defer { try? file.close() }
    var hasher = SHA256()
    do {
      while let data = try file.read(upToCount: chunkSize), !data.isEmpty {
        hasher.update(data: data)
      }
    } catch {
      throw ModelAssetDigestError.assetUnreadable
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func isSHA256Digest(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy { $0.isASCII && $0.isHexDigit }
  }
}
