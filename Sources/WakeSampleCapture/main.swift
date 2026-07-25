import AVFoundation
import Foundation
import cerberusCore

@main
struct WakeSampleCaptureCommand {
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

        let label = try WakeWordSampleDataset.normalizedLabel(options.label)
        print("output: \(options.outputDirectory.path)")
        print("label: \(label)")
        print("count: \(options.count)")
        print(String(format: "seconds: %.2f", options.seconds))

        for index in 1...options.count {
            let fileURL = try WakeWordSampleDataset.sampleFileURL(
                baseDirectoryURL: options.outputDirectory,
                label: label,
                index: index,
                date: Date()
            )
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if options.prompt {
                print("sample \(index)/\(options.count): press return, then speak \(label)")
                _ = readLine()
            } else {
                print("sample \(index)/\(options.count): recording")
            }

            try recordWAV(to: fileURL, seconds: options.seconds)
            let record = WakeWordSampleRecord(
                label: label,
                relativePath: WakeWordSampleDataset.relativePath(for: fileURL, baseDirectoryURL: options.outputDirectory),
                durationSeconds: options.seconds,
                note: options.note
            )
            try WakeWordSampleDataset.write(record: record, to: options.outputDirectory)
            print("wrote: \(record.relativePath)")

            if index < options.count, options.gapSeconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(options.gapSeconds * 1_000_000_000))
            }
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

    private static func recordWAV(to fileURL: URL, seconds: Double) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord() else {
            throw ToolExecutionError.denied("Could not prepare audio recorder.")
        }
        guard recorder.record(forDuration: seconds) else {
            throw ToolExecutionError.denied("Could not start audio recorder.")
        }
        while recorder.isRecording {
            Thread.sleep(forTimeInterval: 0.05)
        }
        recorder.stop()
    }
}

private struct Options {
    let label: String
    let count: Int
    let seconds: Double
    let gapSeconds: Double
    let outputDirectory: URL
    let note: String?
    let prompt: Bool

    init(arguments: [String]) throws {
        var label: String?
        var count = 10
        var seconds = 1.5
        var gapSeconds = 0.5
        var outputDirectory = WakeWordSampleDataset.defaultDirectoryURL()
        var note: String?
        var prompt = true
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--label":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--label requires a value.")
                }
                label = value
            case "--count":
                guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else {
                    throw ToolExecutionError.invalidArguments("--count requires a positive integer.")
                }
                count = parsed
            case "--seconds":
                guard let value = iterator.next(), let parsed = Double(value), parsed > 0 else {
                    throw ToolExecutionError.invalidArguments("--seconds requires a positive number.")
                }
                seconds = parsed
            case "--gap":
                guard let value = iterator.next(), let parsed = Double(value), parsed >= 0 else {
                    throw ToolExecutionError.invalidArguments("--gap requires a non-negative number.")
                }
                gapSeconds = parsed
            case "--output":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--output requires a path.")
                }
                outputDirectory = URL(fileURLWithPath: value)
            case "--note":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--note requires text.")
                }
                note = value
            case "--no-prompt":
                prompt = false
            default:
                throw ToolExecutionError.invalidArguments("Unknown argument: \(argument)")
            }
        }

        guard let label else {
            throw ToolExecutionError.invalidArguments("--label is required.")
        }

        self.label = label
        self.count = count
        self.seconds = seconds
        self.gapSeconds = gapSeconds
        self.outputDirectory = outputDirectory
        self.note = note
        self.prompt = prompt
    }

    static func printUsage() {
        print("""
        usage: cerberus-wake-samples --label hey_cerberus [--count 20] [--seconds 1.5] [--gap 0.5] [--output dir] [--note text] [--no-prompt]

        Records mono 16 kHz WAV files from the active microphone into label folders and appends manifest.jsonl.
        Use labels such as hey_cerberus, background, music, keyboard, walking, and noisy_room.
        """)
    }
}
