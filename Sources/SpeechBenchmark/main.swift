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

        if let expectedText = options.expectedText {
            let rate = SpeechBenchmarkScorer.wordErrorRate(expected: expectedText, actual: latestTranscript)
            print(String(format: "word error rate: %.4f", rate))
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
    let verbose: Bool

    init(arguments: [String]) throws {
        var seconds = 8.0
        var locale = Locale.current
        var expectedText: String?
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
            case "--verbose":
                verbose = true
            default:
                throw ToolExecutionError.invalidArguments("Unknown argument: \(argument)")
            }
        }

        self.seconds = seconds
        self.locale = locale
        self.expectedText = expectedText
        self.verbose = verbose
    }

    static func printUsage() {
        print("""
        usage: cerberus-speech-benchmark [--seconds 8] [--locale en-US] [--expected text] [--verbose]

        Records from the current macOS input device with SpeechAnalyzer and reports transcript latency plus optional word error rate.
        Select AirPods as the macOS input device before running an AirPods benchmark.
        """)
    }
}
