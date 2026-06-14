import AVFoundation
import Foundation
import Speech

public struct TranscriptionUpdate: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

public enum TranscriptionError: Error, LocalizedError {
    case localeNotSupported(Locale)
    case analyzerNotStarted

    public var errorDescription: String? {
        switch self {
        case .localeNotSupported(let locale):
            "Speech transcription does not support locale \(locale.identifier)."
        case .analyzerNotStarted:
            "Speech analyzer is not running."
        }
    }
}

@MainActor
public final class Transcriber {
    private let audioEngine = AVAudioEngine()

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<Void, Never>?
    private var finalizedText = ""
    private var volatileText = ""

    public private(set) var isRunning = false

    public init() {}

    public func start(
        locale requestedLocale: Locale = .current,
        onUpdate: @escaping @MainActor @Sendable (TranscriptionUpdate) -> Void
    ) async throws {
        guard !isRunning else {
            return
        }

        let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale)
        guard let locale = supportedLocale else {
            throw TranscriptionError.localeNotSupported(requestedLocale)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        try await installAssetsIfNeeded(for: transcriber)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let (inputSequence, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)

        self.analyzer = analyzer
        self.transcriber = transcriber
        self.inputContinuation = inputContinuation
        finalizedText = ""
        volatileText = ""

        resultTask = Task { [transcriber] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    await MainActor.run {
                        self.apply(resultText: text, isFinal: result.isFinal, onUpdate: onUpdate)
                    }
                }
            } catch {
                await MainActor.run {
                    onUpdate(TranscriptionUpdate(text: error.localizedDescription, isFinal: true))
                }
            }
        }

        try installAudioTap(format: analyzerFormat, continuation: inputContinuation)
        try await analyzer.start(inputSequence: inputSequence)
        isRunning = true
    }

    public func stop() async {
        guard isRunning else {
            return
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputContinuation?.finish()

        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            try? analyzer?.cancelAndFinishNow()
        }

        resultTask?.cancel()
        resultTask = nil
        inputContinuation = nil
        analyzer = nil
        transcriber = nil
        isRunning = false
    }

    public func cancel() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputContinuation?.finish()
        try? analyzer?.cancelAndFinishNow()
        resultTask?.cancel()
        resultTask = nil
        inputContinuation = nil
        analyzer = nil
        transcriber = nil
        finalizedText = ""
        volatileText = ""
        isRunning = false
    }

    private func installAssetsIfNeeded(for transcriber: SpeechTranscriber) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    private func installAudioTap(
        format analyzerFormat: AVAudioFormat,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            do {
                let converted = try AudioBufferConverter.convert(buffer, to: analyzerFormat)
                continuation.yield(AnalyzerInput(buffer: converted))
            } catch {
                continuation.finish()
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func apply(
        resultText: String,
        isFinal: Bool,
        onUpdate: @MainActor @Sendable (TranscriptionUpdate) -> Void
    ) {
        if isFinal {
            finalizedText += resultText
            volatileText = ""
        } else {
            volatileText = resultText
        }

        let combinedText = [finalizedText, volatileText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        onUpdate(TranscriptionUpdate(text: combinedText, isFinal: isFinal))
    }
}
