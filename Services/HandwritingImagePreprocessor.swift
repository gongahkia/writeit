import CoreImage
import ImageIO

enum ImagePreprocessingStage: String, CaseIterable, Hashable {
  case decode
  case grayscale
  case contrast
}

struct HandwritingImagePreprocessingResult {
  let image: CGImage
  let stageDurations: [ImagePreprocessingStage: Duration]
}

enum HandwritingImagePreprocessor {
  static func process(_ data: Data) -> HandwritingImagePreprocessingResult? {
    let clock = ContinuousClock()
    var stageDurations: [ImagePreprocessingStage: Duration] = [:]

    let decodeStartedAt = clock.now
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    stageDurations[.decode] = clock.now - decodeStartedAt

    let grayscaleStartedAt = clock.now
    guard let grayscale = CIFilter(name: "CIColorControls") else { return nil }
    grayscale.setValue(CIImage(cgImage: decoded), forKey: kCIInputImageKey)
    grayscale.setValue(0, forKey: kCIInputSaturationKey)
    guard let grayscaleImage = grayscale.outputImage else { return nil }
    stageDurations[.grayscale] = clock.now - grayscaleStartedAt

    let contrastStartedAt = clock.now
    guard let contrast = CIFilter(name: "CIColorControls") else { return nil }
    contrast.setValue(grayscaleImage, forKey: kCIInputImageKey)
    contrast.setValue(1.45, forKey: kCIInputContrastKey)
    guard let contrastedImage = contrast.outputImage,
      let image = CIContext().createCGImage(contrastedImage, from: contrastedImage.extent)
    else { return nil }
    stageDurations[.contrast] = clock.now - contrastStartedAt

    return HandwritingImagePreprocessingResult(image: image, stageDurations: stageDurations)
  }
}
