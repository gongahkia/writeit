import AppKit
import Vision

struct OCRCandidate: Equatable {
  var text: String
  var confidence: Float
  var source: String
}

final class RecognitionService: TextRecognizing {
  private let enhanced = EnhancedOCRAdapter()

  func recognize(image: NSImage) async -> OCRCandidate? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }
    let vision = await Task.detached(priority: .userInitiated) { Self.runVision(cgImage) }.value
    let localModel = await enhanced.recognize(image: cgImage)
    return [vision, localModel].compactMap { $0 }.max { $0.confidence < $1.confidence }
  }

  private static func runVision(_ image: CGImage) -> OCRCandidate? {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["en-US"]
    request.minimumTextHeight = 0.012
    let handler = VNImageRequestHandler(cgImage: image)
    do { try handler.perform([request]) } catch { return nil }
    let results = (request.results ?? []).sorted { $0.boundingBox.minY > $1.boundingBox.minY }
    let candidates = results.compactMap { $0.topCandidates(1).first }
    guard !candidates.isEmpty else { return nil }
    return OCRCandidate(
      text: TextSanitizer.normalize(candidates.map(\.string).joined(separator: " ")),
      confidence: candidates.map(\.confidence).reduce(0, +) / Float(candidates.count),
      source: "Apple Vision"
    )
  }
}

final class EnhancedOCRAdapter {
  var isInstalled: Bool {
    Bundle.main.url(forResource: "TrOCRSmallHandwritten", withExtension: "mlmodelc") != nil
  }

  func recognize(image: CGImage) async -> OCRCandidate? {
    nil
  }
}

enum TextSanitizer {
  static func normalize(_ input: String) -> String {
    let trimmed = input.precomposedStringWithCanonicalMapping.trimmingCharacters(
      in: .whitespacesAndNewlines)
    return trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }
}
