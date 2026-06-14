import AVFoundation
import Foundation

public enum Earcon: Sendable {
    case wake
    case cancel
    case reasoning
    case confirmation
    case executing
    case speaking
    case error

    var frequencies: [Double] {
        switch self {
        case .wake:
            [660, 880]
        case .cancel:
            [330, 220]
        case .reasoning:
            [520]
        case .confirmation:
            [740, 740]
        case .executing:
            [440, 660, 440]
        case .speaking:
            [880]
        case .error:
            [180, 180]
        }
    }
}

@MainActor
public final class EarconPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    public init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    public func play(for transition: AssistantTransition) {
        if case .failed = transition.event {
            play(.error)
            return
        }

        switch transition.to {
        case .idle:
            play(.cancel)
        case .listening:
            play(.wake)
        case .reasoning:
            play(.reasoning)
        case .awaitingConfirm:
            play(.confirmation)
        case .executing:
            play(.executing)
        case .speaking:
            play(.speaking)
        }
    }

    public func play(_ earcon: Earcon) {
        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            return
        }

        if !player.isPlaying {
            player.play()
        }

        for frequency in earcon.frequencies {
            if let buffer = makeToneBuffer(frequency: frequency, duration: 0.08) {
                player.scheduleBuffer(buffer, completionHandler: nil)
            }
        }
    }

    private func makeToneBuffer(frequency: Double, duration: TimeInterval) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData?[0] else {
            return nil
        }

        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            let envelope = min(Double(frame) / 300.0, 1.0)
            channelData[frame] = Float(sin(2.0 * .pi * frequency * time) * 0.12 * envelope)
        }

        return buffer
    }
}
