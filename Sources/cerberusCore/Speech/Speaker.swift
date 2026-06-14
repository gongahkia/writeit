import AVFoundation
import Foundation

@MainActor
public final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (@MainActor @Sendable () -> Void)?

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    public func speak(
        _ text: String,
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        stop()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.prefersAssistiveTechnologySettings = true
        self.completion = completion
        synthesizer.speak(utterance)
    }

    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            completion?()
            completion = nil
        }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            completion = nil
        }
    }
}
