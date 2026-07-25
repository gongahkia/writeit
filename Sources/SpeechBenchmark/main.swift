import AVFoundation
import Foundation
import cerberusCore

@main
struct SpeechBenchmarkCommand {
    @MainActor
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("-h") || arguments.contains("--help") {
            Options.printUsage()
            return
        }

        let options = try Options(arguments: arguments)
        guard await requestMicrophoneAccess() else {
            throw ToolExecutionError.denied("Microphone access is not granted.")
        }

        let transcriber = Transcriber()
        let start = Date()
        var firstUpdateAt: Date?
        var latestTranscript = ""
        var finalUpdateCount = 0
        var updateCount = 0

        print("locale: \(options.locale.identifier)")
        print(String(format: "seconds: %.2f", options.seconds))
        print("expected: \(options.expectedText ?? "")")
        print("recording...")

        try await transcriber.start(locale: options.locale) { update in
            updateCount += 1
            if firstUpdateAt == nil, !update.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                firstUpdateAt = Date()
            }
            if update.isFinal {
                finalUpdateCount += 1
            }
            latestTranscript = update.text
            if options.verbose {
                print("update final=\(update.isFinal): \(update.text)")
            }
        }

        try await Task.sleep(nanoseconds: UInt64(options.seconds * 1_000_000_000))
        try Task.checkCancellation()
        let stopRequestedAt = Date()
        await transcriber.stop()
        let stoppedAt = Date()

        print("transcript: \(latestTranscript)")
        print("updates: \(updateCount)")
        print("final updates: \(finalUpdateCount)")
        if let firstUpdateAt {
            print(String(format: "first update latency: %.3fs", firstUpdateAt.timeIntervalSince(start)))
        } else {
            print("first update latency: unavailable")
        }
        print(String(format: "record duration: %.3fs", stopRequestedAt.timeIntervalSince(start)))
        print(String(format: "finalize duration: %.3fs", stoppedAt.timeIntervalSince(stopRequestedAt)))

        let firstUpdateLatency = firstUpdateAt.map { $0.timeIntervalSince(start) }
        let recordDuration = stopRequestedAt.timeIntervalSince(start)
        let finalizeDuration = stoppedAt.timeIntervalSince(stopRequestedAt)
        let wordErrorRate = options.expectedText.map {
            SpeechBenchmarkScorer.wordErrorRate(expected: $0, actual: latestTranscript)
        }

        if let wordErrorRate {
            let rate = wordErrorRate
            print(String(format: "word error rate: %.4f", rate))
        }

        if let outputURL = options.outputURL {
            let report = SpeechBenchmarkReport(
                startedAt: start,
                localeIdentifier: options.locale.identifier,
                seconds: options.seconds,
                expectedText: options.expectedText,
                transcript: latestTranscript,
                updateCount: updateCount,
                finalUpdateCount: finalUpdateCount,
                firstUpdateLatencySeconds: firstUpdateLatency,
                recordDurationSeconds: recordDuration,
                finalizeDurationSeconds: finalizeDuration,
                wordErrorRate: wordErrorRate
            )
            try BenchmarkReportWriter.write(report, to: outputURL)
            print("wrote report: \(outputURL.path)")
        }
    }

    private static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }
}

private struct Options {
    let seconds: Double
    let locale: Locale
    let expectedText: String?
    let outputURL: URL?
    let verbose: Bool

    init(arguments: [String]) throws {
        var seconds = 8.0
        var locale = Locale.current
        var expectedText: String?
        var outputURL: URL?
        var verbose = false
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--seconds":
                guard let value = iterator.next(), let parsed = Double(value), parsed > 0 else {
                    throw ToolExecutionError.invalidArguments("--seconds requires a positive number.")
                }
                seconds = parsed
            case "--locale":
                guard let value = iterator.next(), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ToolExecutionError.invalidArguments("--locale requires a locale identifier.")
                }
                locale = Locale(identifier: value)
            case "--expected":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--expected requires text.")
                }
                expectedText = value
            case "--output":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--output requires a path.")
                }
                outputURL = Self.fileURL(value)
            case "--verbose":
                verbose = true
            default:
                throw ToolExecutionError.invalidArguments("Unknown argument: \(argument)")
            }
        }

        self.seconds = seconds
        self.locale = locale
        self.expectedText = expectedText
        self.outputURL = outputURL
        self.verbose = verbose
    }

    static func printUsage() {
        print("""
        usage: cerberus-speech-benchmark [--seconds 8] [--locale en-US] [--expected text] [--output report.json] [--verbose]

        Records from the current macOS input device with SpeechAnalyzer and reports transcript latency plus optional word error rate.
        Select AirPods as the macOS input device before running an AirPods benchmark.
        """)
    }

    private static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}

private struct SpeechBenchmarkReport: Encodable {
    let tool = "cerberus-speech-benchmark"
    let startedAt: Date
    let localeIdentifier: String
    let seconds: Double
    let expectedText: String?
    let transcript: String
    let updateCount: Int
    let finalUpdateCount: Int
    let firstUpdateLatencySeconds: Double?
    let recordDurationSeconds: Double
    let finalizeDurationSeconds: Double
    let wordErrorRate: Double?
}
