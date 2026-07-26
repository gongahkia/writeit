import CoreML
import CoreVideo
import Foundation

enum TrOCRError: LocalizedError, Equatable {
  case bundleUnavailable
  case invalidBundle
  case invalidModelOutput
  case decodingFailed

  var errorDescription: String? {
    switch self {
    case .bundleUnavailable: "The downloaded TrOCR model is unavailable."
    case .invalidBundle: "The downloaded TrOCR bundle is invalid."
    case .invalidModelOutput: "The downloaded TrOCR model returned an invalid result."
    case .decodingFailed: "WriteIt could not decode TrOCR output."
    }
  }
}

struct TrOCRTokenizerConfiguration: Codable, Equatable {
  let vocabulary: [String: Int]
  let beginningOfSentenceTokenID: Int
  let endOfSentenceTokenID: Int
  let paddingTokenID: Int

  enum CodingKeys: String, CodingKey {
    case vocabulary
    case beginningOfSentenceTokenID = "bos_token_id"
    case endOfSentenceTokenID = "eos_token_id"
    case paddingTokenID = "pad_token_id"
  }
}

struct TrOCRTokenizer: Equatable {
  private let tokensByID: [Int: String]
  let beginningOfSentenceTokenID: Int
  let endOfSentenceTokenID: Int
  let paddingTokenID: Int

  init(configuration: TrOCRTokenizerConfiguration) throws {
    guard !configuration.vocabulary.isEmpty,
      configuration.vocabulary.values.allSatisfy({ $0 >= 0 }),
      configuration.vocabulary.values.count == Set(configuration.vocabulary.values).count,
      configuration.vocabulary.values.contains(configuration.beginningOfSentenceTokenID),
      configuration.vocabulary.values.contains(configuration.endOfSentenceTokenID),
      configuration.vocabulary.values.contains(configuration.paddingTokenID)
    else { throw TrOCRError.invalidBundle }
    tokensByID = Dictionary(uniqueKeysWithValues: configuration.vocabulary.map { ($0.value, $0.key) })
    beginningOfSentenceTokenID = configuration.beginningOfSentenceTokenID
    endOfSentenceTokenID = configuration.endOfSentenceTokenID
    paddingTokenID = configuration.paddingTokenID
  }

  func decode(_ tokenIDs: [Int]) -> String {
    var result = ""
    for tokenID in tokenIDs where tokenID != beginningOfSentenceTokenID && tokenID != endOfSentenceTokenID && tokenID != paddingTokenID {
      guard let token = tokensByID[tokenID], !token.hasPrefix("<") else { continue }
      if token.hasPrefix("##") {
        result += String(token.dropFirst(2))
      } else if token.hasPrefix("▁") || token.hasPrefix("Ġ") {
        let word = String(token.dropFirst())
        if !result.isEmpty && !result.hasSuffix(" ") { result += " " }
        result += word
      } else {
        result += token
      }
    }
    return TextSanitizer.normalize(result)
  }
}

protocol TrOCRLogitsPredicting {
  func logits(for tokenIDs: [Int]) throws -> [Float]
}

struct TrOCRGreedyDecoder {
  let tokenizer: TrOCRTokenizer
  let maximumTokenCount: Int

  init(tokenizer: TrOCRTokenizer, maximumTokenCount: Int) throws {
    guard (1...256).contains(maximumTokenCount) else { throw TrOCRError.invalidBundle }
    self.tokenizer = tokenizer
    self.maximumTokenCount = maximumTokenCount
  }

  func decode(using predictor: any TrOCRLogitsPredicting) throws -> String {
    var tokenIDs = [tokenizer.beginningOfSentenceTokenID]
    for _ in 0..<maximumTokenCount {
      let logits = try predictor.logits(for: tokenIDs)
      guard let nextToken = logits.enumerated().max(by: { $0.element < $1.element })?.offset else {
        throw TrOCRError.invalidModelOutput
      }
      tokenIDs.append(nextToken)
      if nextToken == tokenizer.endOfSentenceTokenID { break }
    }
    let text = tokenizer.decode(tokenIDs)
    guard !text.isEmpty else { throw TrOCRError.decodingFailed }
    return text
  }
}

private struct TrOCRRuntimeConfiguration: Codable {
  let schemaVersion: Int
  let encoderModelFile: String
  let decoderModelFile: String
  let encoderInputName: String
  let encoderOutputName: String
  let decoderEncoderInputName: String
  let decoderTokenInputName: String
  let decoderLogitsOutputName: String
  let imageWidth: Int
  let imageHeight: Int
  let decoderTokenCount: Int
  let maximumGeneratedTokens: Int

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case encoderModelFile = "encoder_model_file"
    case decoderModelFile = "decoder_model_file"
    case encoderInputName = "encoder_input_name"
    case encoderOutputName = "encoder_output_name"
    case decoderEncoderInputName = "decoder_encoder_input_name"
    case decoderTokenInputName = "decoder_token_input_name"
    case decoderLogitsOutputName = "decoder_logits_output_name"
    case imageWidth = "image_width"
    case imageHeight = "image_height"
    case decoderTokenCount = "decoder_token_count"
    case maximumGeneratedTokens = "maximum_generated_tokens"
  }

  var isValid: Bool {
    schemaVersion == 1 && !encoderModelFile.contains("/") && !decoderModelFile.contains("/")
      && imageWidth > 0 && imageHeight > 0 && decoderTokenCount > 0 && maximumGeneratedTokens > 0
  }
}

private struct TrOCRCoreMLPredictor: TrOCRLogitsPredicting {
  let decoder: MLModel
  let encoderOutput: MLFeatureValue
  let configuration: TrOCRRuntimeConfiguration
  let tokenizer: TrOCRTokenizer
  let vocabularySize: Int

  func logits(for tokenIDs: [Int]) throws -> [Float] {
    guard tokenIDs.count <= configuration.decoderTokenCount else { throw TrOCRError.decodingFailed }
    let values = try MLMultiArray(
      shape: [NSNumber(value: 1), NSNumber(value: configuration.decoderTokenCount)], dataType: .int32)
    for index in 0..<configuration.decoderTokenCount {
      values[index] = NSNumber(value: index < tokenIDs.count ? tokenIDs[index] : tokenizer.paddingTokenID)
    }
    let inputs = try MLDictionaryFeatureProvider(dictionary: [
      configuration.decoderEncoderInputName: encoderOutput,
      configuration.decoderTokenInputName: MLFeatureValue(multiArray: values),
    ])
    let output = try decoder.prediction(from: inputs)
    guard let logits = output.featureValue(for: configuration.decoderLogitsOutputName)?.multiArrayValue,
      logits.count >= vocabularySize
    else { throw TrOCRError.invalidModelOutput }
    let finalOffset = logits.count - vocabularySize
    return (0..<vocabularySize).map { logits[finalOffset + $0].floatValue }
  }
}

private struct TrOCRCoreMLBundle {
  let tokenizer: TrOCRTokenizer
  let configuration: TrOCRRuntimeConfiguration
  let encoder: MLModel
  let decoder: MLModel

  init(bundleURL: URL) throws {
    let configurationURL = bundleURL.appendingPathComponent("writeit-trocr-runtime.json")
    let tokenizerURL = bundleURL.appendingPathComponent("writeit-trocr-tokenizer.json")
    let configuration = try JSONDecoder().decode(
      TrOCRRuntimeConfiguration.self, from: Data(contentsOf: configurationURL))
    guard configuration.isValid else { throw TrOCRError.invalidBundle }
    let tokenizerConfiguration = try JSONDecoder().decode(
      TrOCRTokenizerConfiguration.self, from: Data(contentsOf: tokenizerURL))
    tokenizer = try TrOCRTokenizer(configuration: tokenizerConfiguration)
    self.configuration = configuration
    encoder = try MLModel(contentsOf: bundleURL.appendingPathComponent(configuration.encoderModelFile))
    decoder = try MLModel(contentsOf: bundleURL.appendingPathComponent(configuration.decoderModelFile))
  }

  func recognize(_ image: CGImage) throws -> String {
    let imageValue = try MLFeatureValue(
      cgImage: image,
      pixelsWide: configuration.imageWidth,
      pixelsHigh: configuration.imageHeight,
      pixelFormatType: kCVPixelFormatType_32BGRA,
      options: [:]
    )
    let encoderInputs = try MLDictionaryFeatureProvider(dictionary: [configuration.encoderInputName: imageValue])
    let encoderOutput = try encoder.prediction(from: encoderInputs)
    guard let output = encoderOutput.featureValue(for: configuration.encoderOutputName) else {
      throw TrOCRError.invalidModelOutput
    }
    let predictor = TrOCRCoreMLPredictor(
      decoder: decoder,
      encoderOutput: output,
      configuration: configuration,
      tokenizer: tokenizer,
      vocabularySize: tokenizerVocabularySize
    )
    return try TrOCRGreedyDecoder(
      tokenizer: tokenizer, maximumTokenCount: configuration.maximumGeneratedTokens
    ).decode(using: predictor)
  }

  private var tokenizerVocabularySize: Int {
    tokenizer.maximumTokenID + 1
  }
}

private extension TrOCRTokenizer {
  var maximumTokenID: Int { tokensByID.keys.max() ?? 0 }
}

actor TrOCRCoreMLAdapter {
  private let modelsDirectory: URL

  init(modelsDirectory: URL? = nil) {
    self.modelsDirectory = modelsDirectory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("WriteIt/Models", isDirectory: true)
  }

  func recognize(imageData: Data) throws -> RecognitionResult? {
    guard let bundleURL = installedBundleURL() else { return nil }
    guard let image = HandwritingImagePreprocessor.process(imageData)?.image else {
      throw RecognitionError.invalidImage
    }
    do {
      let bundle = try TrOCRCoreMLBundle(bundleURL: bundleURL)
      let text = try bundle.recognize(image)
      return RecognitionResult(text: text, confidence: 0.9, backendID: "trocr-small-handwritten")
    } catch {
      AppLog.recognition.error("trocr_bundle_unavailable type=\(AppLog.errorType(error), privacy: .public)")
      return nil
    }
  }

  private func installedBundleURL() -> URL? {
    let identifierDirectory = modelsDirectory.appendingPathComponent("trocr-small-handwritten", isDirectory: true)
    let versions: [URL]
    do {
      versions = try FileManager.default.contentsOfDirectory(
        at: identifierDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
      ).sorted { $0.lastPathComponent > $1.lastPathComponent }
    } catch {
      return nil
    }
    for version in versions {
      guard let entries = try? FileManager.default.contentsOfDirectory(
        at: version, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
      else { continue }
      if let bundle = entries.first(where: { $0.lastPathComponent == "bundle" }) {
        return bundle
      }
    }
    return nil
  }
}
