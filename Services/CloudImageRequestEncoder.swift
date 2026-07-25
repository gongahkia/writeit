import CoreGraphics
import Foundation
import ImageIO

struct CloudEncodedImage: Sendable {
  let data: Data
  let contentType: String
}

enum CloudImageRequestEncodingError: LocalizedError, Equatable {
  case invalidImage
  case tooLarge

  var errorDescription: String? {
    switch self {
    case .invalidImage: "WriteIt could not prepare the captured ink for cloud OCR."
    case .tooLarge: "The captured ink is too large for cloud OCR."
    }
  }
}

enum CloudRequestPolicy {
  static let timeoutInterval: TimeInterval = 30
}

enum CloudImageRequestEncoder {
  static let maximumEncodedBytes = 7_000_000
  static let maximumDimension = 2_048

  static func encode(
    _ imageData: Data,
    maximumBytes: Int = maximumEncodedBytes
  ) throws -> CloudEncodedImage {
    guard maximumBytes > 0,
      let image = HandwritingImagePreprocessor.process(imageData)?.image,
      let scaledImage = scaled(image)
    else { throw CloudImageRequestEncodingError.invalidImage }
    for quality in [0.9, 0.75, 0.6] {
      let data = try jpegData(for: scaledImage, quality: quality)
      if data.count <= maximumBytes { return CloudEncodedImage(data: data, contentType: "image/jpeg") }
    }
    throw CloudImageRequestEncodingError.tooLarge
  }

  private static func scaled(_ image: CGImage) -> CGImage? {
    let longestEdge = max(image.width, image.height)
    guard longestEdge > 0 else { return nil }
    let scale = min(1, CGFloat(maximumDimension) / CGFloat(longestEdge))
    guard scale < 1 else { return image }
    let width = max(1, Int((CGFloat(image.width) * scale).rounded(.toNearestOrAwayFromZero)))
    let height = max(1, Int((CGFloat(image.height) * scale).rounded(.toNearestOrAwayFromZero)))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  private static func jpegData(for image: CGImage, quality: CGFloat) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)
    else { throw CloudImageRequestEncodingError.invalidImage }
    CGImageDestinationAddImage(
      destination,
      image,
      [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
      throw CloudImageRequestEncodingError.invalidImage
    }
    return data as Data
  }
}
