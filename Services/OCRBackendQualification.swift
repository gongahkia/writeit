import Foundation

enum OCRBackendQualificationThresholdError: Error, Equatable {
  case invalidErrorRate
  case negativeDuration
}

struct OCRBackendQualificationThresholds: Equatable, Sendable {
  let maximumMeanCharacterErrorRate: Double
  let maximumMeanWordErrorRate: Double
  let maximumSampleDuration: Duration
  let maximumTotalDuration: Duration
  let maximumPeakResidentMemoryBytes: UInt64?

  init(
    maximumMeanCharacterErrorRate: Double,
    maximumMeanWordErrorRate: Double,
    maximumSampleDuration: Duration,
    maximumTotalDuration: Duration,
    maximumPeakResidentMemoryBytes: UInt64? = nil
  ) throws {
    guard (0...1).contains(maximumMeanCharacterErrorRate),
      (0...1).contains(maximumMeanWordErrorRate)
    else {
      throw OCRBackendQualificationThresholdError.invalidErrorRate
    }
    guard maximumSampleDuration >= .zero, maximumTotalDuration >= .zero else {
      throw OCRBackendQualificationThresholdError.negativeDuration
    }
    self.maximumMeanCharacterErrorRate = maximumMeanCharacterErrorRate
    self.maximumMeanWordErrorRate = maximumMeanWordErrorRate
    self.maximumSampleDuration = maximumSampleDuration
    self.maximumTotalDuration = maximumTotalDuration
    self.maximumPeakResidentMemoryBytes = maximumPeakResidentMemoryBytes
  }
}

struct OCRBackendQualificationMetrics: Equatable, Sendable {
  let sampleCount: Int
  let meanCharacterErrorRate: Double?
  let meanWordErrorRate: Double?
  let maximumSampleDuration: Duration?
  let totalDuration: Duration
  let peakResidentMemoryBytes: UInt64?
}

enum OCRBackendQualificationFailure: Equatable, Sendable {
  case noSamples
  case failedSamples(Int)
  case unexpectedBackendSamples(Int)
  case characterErrorRate(Double)
  case wordErrorRate(Double)
  case sampleDuration(Duration)
  case totalDuration(Duration)
  case memoryUnavailable
  case peakResidentMemory(UInt64)
}

struct OCRBackendQualification: Equatable, Sendable {
  let backendID: String
  let metrics: OCRBackendQualificationMetrics
  let failures: [OCRBackendQualificationFailure]

  var isQualified: Bool { failures.isEmpty }
}

enum OCRBackendQualifier {
  static func qualify(
    report: OCRBenchmarkReport,
    backendID: String,
    thresholds: OCRBackendQualificationThresholds
  ) -> OCRBackendQualification {
    let successfulSamples = report.samples.compactMap { sample -> OCRCorpusBenchmarkSample? in
      guard case .recognized(_, _, let sampleBackendID) = sample.outcome,
        sampleBackendID == backendID
      else { return nil }
      return sample
    }
    let failedSampleCount = report.samples.count { sample in
      if case .failed = sample.outcome { return true }
      return false
    }
    let unexpectedBackendSampleCount = report.samples.count { sample in
      guard case .recognized(_, _, let sampleBackendID) = sample.outcome else { return false }
      return sampleBackendID != backendID
    }
    let characterErrorRates = successfulSamples.compactMap { sample -> Double? in
      guard case .recognized(let text, _, _) = sample.outcome else { return nil }
      return OCRAccuracyEvaluator.characterErrorRate(expected: sample.expectedText, actual: text)
    }
    let wordErrorRates = successfulSamples.compactMap { sample -> Double? in
      guard case .recognized(let text, _, _) = sample.outcome else { return nil }
      return OCRAccuracyEvaluator.wordErrorRate(expected: sample.expectedText, actual: text)
    }
    let metrics = OCRBackendQualificationMetrics(
      sampleCount: successfulSamples.count,
      meanCharacterErrorRate: mean(of: characterErrorRates),
      meanWordErrorRate: mean(of: wordErrorRates),
      maximumSampleDuration: successfulSamples.map(\.duration).max(),
      totalDuration: report.totalDuration,
      peakResidentMemoryBytes: report.peakResidentMemoryBytes
    )
    var failures: [OCRBackendQualificationFailure] = []
    if report.samples.isEmpty { failures.append(.noSamples) }
    if failedSampleCount > 0 { failures.append(.failedSamples(failedSampleCount)) }
    if unexpectedBackendSampleCount > 0 {
      failures.append(.unexpectedBackendSamples(unexpectedBackendSampleCount))
    }
    if let rate = metrics.meanCharacterErrorRate, rate > thresholds.maximumMeanCharacterErrorRate {
      failures.append(.characterErrorRate(rate))
    }
    if let rate = metrics.meanWordErrorRate, rate > thresholds.maximumMeanWordErrorRate {
      failures.append(.wordErrorRate(rate))
    }
    if let duration = metrics.maximumSampleDuration, duration > thresholds.maximumSampleDuration {
      failures.append(.sampleDuration(duration))
    }
    if metrics.totalDuration > thresholds.maximumTotalDuration {
      failures.append(.totalDuration(metrics.totalDuration))
    }
    if let maximumMemory = thresholds.maximumPeakResidentMemoryBytes {
      guard let peakMemory = metrics.peakResidentMemoryBytes else {
        failures.append(.memoryUnavailable)
        return OCRBackendQualification(backendID: backendID, metrics: metrics, failures: failures)
      }
      if peakMemory > maximumMemory { failures.append(.peakResidentMemory(peakMemory)) }
    }
    return OCRBackendQualification(backendID: backendID, metrics: metrics, failures: failures)
  }

  private static func mean(of values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
  }
}
