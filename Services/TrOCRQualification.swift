import Foundation

struct TrOCRQualificationPolicy {
  static let maximumSampleDuration: Duration = .milliseconds(1_500)
  static let maximumTotalDuration: Duration = .seconds(15)
  static let maximumPeakResidentMemoryBytes: UInt64 = 1_500 * 1_024 * 1_024
}

struct TrOCRBenchmarkMetrics: Codable, Equatable {
  let sampleCount: Int
  let meanCharacterErrorRate: Double?
  let meanWordErrorRate: Double?
  let maximumSampleDurationMilliseconds: Double?
  let totalDurationMilliseconds: Double
  let peakResidentMemoryBytes: UInt64?

  init(_ metrics: OCRBackendQualificationMetrics) {
    sampleCount = metrics.sampleCount
    meanCharacterErrorRate = metrics.meanCharacterErrorRate
    meanWordErrorRate = metrics.meanWordErrorRate
    maximumSampleDurationMilliseconds = metrics.maximumSampleDuration.map(Self.milliseconds)
    totalDurationMilliseconds = Self.milliseconds(metrics.totalDuration)
    peakResidentMemoryBytes = metrics.peakResidentMemoryBytes
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}

struct TrOCRQualificationArtifact: Codable, Equatable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let modelID: String
  let isQualified: Bool
  let failures: [String]
  let vision: TrOCRBenchmarkMetrics
  let trocr: TrOCRBenchmarkMetrics

  init(vision: OCRBackendQualificationMetrics, trocr: OCRBackendQualificationMetrics) {
    schemaVersion = Self.currentSchemaVersion
    modelID = "trocr-small-handwritten"
    self.vision = TrOCRBenchmarkMetrics(vision)
    self.trocr = TrOCRBenchmarkMetrics(trocr)
    failures = Self.failures(vision: self.vision, trocr: self.trocr)
    isQualified = failures.isEmpty
  }

  private static func failures(
    vision: TrOCRBenchmarkMetrics,
    trocr: TrOCRBenchmarkMetrics
  ) -> [String] {
    var failures: [String] = []
    guard trocr.sampleCount > 0 else {
      failures.append("trocr-no-samples")
      return failures
    }
    guard vision.sampleCount == trocr.sampleCount else { failures.append("sample-count-mismatch"); return failures }
    guard let visionCER = vision.meanCharacterErrorRate,
      let trocrCER = trocr.meanCharacterErrorRate,
      trocrCER < visionCER
    else { failures.append("character-error-not-improved"); return failures }
    guard let visionWER = vision.meanWordErrorRate,
      let trocrWER = trocr.meanWordErrorRate,
      trocrWER < visionWER
    else { failures.append("word-error-not-improved"); return failures }
    guard let sampleDuration = trocr.maximumSampleDurationMilliseconds,
      sampleDuration <= milliseconds(TrOCRQualificationPolicy.maximumSampleDuration)
    else { failures.append("sample-duration-exceeded"); return failures }
    guard trocr.totalDurationMilliseconds <= milliseconds(TrOCRQualificationPolicy.maximumTotalDuration) else {
      failures.append("total-duration-exceeded")
      return failures
    }
    guard let memory = trocr.peakResidentMemoryBytes,
      memory <= TrOCRQualificationPolicy.maximumPeakResidentMemoryBytes
    else { failures.append("memory-exceeded") ; return failures }
    return failures
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}

enum TrOCRQualificationStore {
  static let fileName = "trocr-qualification.json"

  static func load(from modelsDirectory: URL) -> TrOCRQualificationArtifact? {
    let url = modelsDirectory.appendingPathComponent(fileName)
    guard let artifact = try? JSONDecoder().decode(TrOCRQualificationArtifact.self, from: Data(contentsOf: url)),
      artifact.schemaVersion == TrOCRQualificationArtifact.currentSchemaVersion,
      artifact.modelID == "trocr-small-handwritten"
    else { return nil }
    return artifact
  }

  static func save(_ artifact: TrOCRQualificationArtifact, to modelsDirectory: URL) throws {
    try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    try JSONEncoder().encode(artifact).write(
      to: modelsDirectory.appendingPathComponent(fileName), options: .atomic)
  }
}

enum TrOCRBenchmarkQualifier {
  static func qualify(
    visionReport: OCRBenchmarkReport,
    trocrReport: OCRBenchmarkReport
  ) throws -> TrOCRQualificationArtifact {
    let permissive = try OCRBackendQualificationThresholds(
      maximumMeanCharacterErrorRate: 1,
      maximumMeanWordErrorRate: 1,
      maximumSampleDuration: .seconds(86_400),
      maximumTotalDuration: .seconds(86_400),
      maximumPeakResidentMemoryBytes: .max
    )
    let vision = OCRBackendQualifier.qualify(
      report: visionReport, backendID: "apple-vision", thresholds: permissive).metrics
    let trocr = OCRBackendQualifier.qualify(
      report: trocrReport, backendID: "trocr-small-handwritten", thresholds: permissive).metrics
    return TrOCRQualificationArtifact(vision: vision, trocr: trocr)
  }
}
