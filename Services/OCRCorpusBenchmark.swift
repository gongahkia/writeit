import Foundation

enum OCRCorpusBenchmarkOutcome: Equatable {
  case recognized(text: String, confidence: Float, backendID: String)
  case failed
}

struct OCRCorpusBenchmarkSample: Equatable {
  let fixtureID: String
  let language: RecognitionLanguage
  let expectedText: String
  let outcome: OCRCorpusBenchmarkOutcome
  let duration: Duration
}

enum OCRCorpusBenchmarkHarness {
  static func run(
    fixtures: [OCRCorpusFixture],
    recognizer: any TextRecognizing
  ) async throws -> [OCRCorpusBenchmarkSample] {
    let clock = ContinuousClock()
    var samples: [OCRCorpusBenchmarkSample] = []
    for fixture in fixtures.sorted(by: { $0.entry.id < $1.entry.id }) {
      try Task.checkCancellation()
      let startedAt = clock.now
      let outcome: OCRCorpusBenchmarkOutcome
      do {
        let result = try await recognizer.recognize(
          RecognitionRequest(imageData: fixture.imageData, language: fixture.entry.language)
        )
        outcome = .recognized(
          text: result.text,
          confidence: result.confidence,
          backendID: result.backendID
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        outcome = .failed
      }
      samples.append(
        OCRCorpusBenchmarkSample(
          fixtureID: fixture.entry.id,
          language: fixture.entry.language,
          expectedText: fixture.entry.transcription,
          outcome: outcome,
          duration: clock.now - startedAt
        )
      )
    }
    return samples
  }
}
