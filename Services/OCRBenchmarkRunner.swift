import Darwin
import Foundation

enum OCRBenchmarkError: Error, Equatable {
  case requiresAppleSilicon
}

struct OCRBenchmarkReport {
  let samples: [OCRCorpusBenchmarkSample]
  let totalDuration: Duration
  let peakResidentMemoryBytes: UInt64?
}

enum OCRBenchmarkRunner {
  static var isAppleSilicon: Bool {
    #if arch(arm64)
      true
    #else
      false
    #endif
  }

  static func run(
    fixtures: [OCRCorpusFixture],
    recognizer: any TextRecognizing
  ) async throws -> OCRBenchmarkReport {
    guard isAppleSilicon else { throw OCRBenchmarkError.requiresAppleSilicon }
    let clock = ContinuousClock()
    let startedAt = clock.now
    var peakResidentMemoryBytes = residentMemoryBytes()
    var samples: [OCRCorpusBenchmarkSample] = []
    for fixture in fixtures.sorted(by: { $0.entry.id < $1.entry.id }) {
      let result = try await OCRCorpusBenchmarkHarness.run(
        fixtures: [fixture],
        recognizer: recognizer
      )
      samples.append(contentsOf: result)
      if let residentMemory = residentMemoryBytes() {
        peakResidentMemoryBytes = max(peakResidentMemoryBytes ?? residentMemory, residentMemory)
      }
    }
    return OCRBenchmarkReport(
      samples: samples,
      totalDuration: clock.now - startedAt,
      peakResidentMemoryBytes: peakResidentMemoryBytes
    )
  }

  private static func residentMemoryBytes() -> UInt64? {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size) : nil
  }
}
