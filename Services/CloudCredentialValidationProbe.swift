import CoreGraphics
import Foundation
import ImageIO

enum CloudCredentialValidationProbe {
  static let imageData: Data = {
    let data = NSMutableData()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil,
      width: 64,
      height: 64,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { preconditionFailure("could not create credential validation probe") }
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
    else { preconditionFailure("could not encode credential validation probe") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      preconditionFailure("could not finalize credential validation probe")
    }
    return data as Data
  }()
}
