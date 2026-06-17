import AVFoundation
import Foundation

public enum Earcon: Equatable, Sendable {
    case wake
    case cancel
    case complete
    case reasoning
    case confirmation
    case approved
    case denied
    case executing
    case speaking
    case toolResult
    case error

    var frequencies: [Double] {
        switch self {
        case .wake:
            [660, 880]
        case .cancel:
            [330, 220]
        case .complete:
            [660, 520]
        case .reasoning:
            [520]
        case .confirmation:
            [740, 740]
        case .approved:
            [660, 880, 990]
        case .denied:
            [260, 220, 180]
        case .executing:
            [440, 660, 440]
        case .speaking:
            [880]
        case .toolResult:
            [880, 660]
        case .error:
            [180, 180]
        }
    }
}

public enum EarconMapper {
    public static func earcon(for transition: AssistantTransition) -> Earcon {
        switch transition.event {
        case .wakeDetected:
            .wake
        case .silenceDetected:
            .reasoning
        case .cancelRequested:
            .cancel
        case .confirmationRequired:
            .confirmation
        case .confirmationAccepted:
            .approved
        case .confirmationDenied:
            .denied
        case .executionStarted:
            .executing
        case .executionFinished:
            .toolResult
        case .responseReady:
            .speaking
        case .speechFinished:
            .complete
        case .failed:
            .error
        case .reset:
            .cancel
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
        play(EarconMapper.earcon(for: transition))
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
