import AudioToolbox
import AVFoundation
import Foundation

@MainActor
public final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private struct SendablePCMBuffer: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var routedSynthesizer: AVSpeechSynthesizer?
    private var routedEngine: AVAudioEngine?
    private var routedPlayer: AVAudioPlayerNode?
    private var routedBuffers: [AVAudioPCMBuffer] = []
    private var routedToken = UUID()
    private var preferredOutputDevice: AudioOutputDevice?
    private var completion: (@MainActor @Sendable () -> Void)?

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    public func setPreferredOutputDevice(_ device: AudioOutputDevice?) {
        preferredOutputDevice = device
    }

    public func speak(
        _ text: String,
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        stop()

        if let preferredOutputDevice {
            speakRouted(text, device: preferredOutputDevice, rate: rate, completion: completion)
            return
        }

        speakWithSystemRoute(text, rate: rate, completion: completion)
    }

    private func speakWithSystemRoute(
        _ text: String,
        rate: Float,
        completion: (@MainActor @Sendable () -> Void)?
    ) {
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
        routedSynthesizer?.stopSpeaking(at: .immediate)
        routedPlayer?.stop()
        routedEngine?.stop()
        routedSynthesizer = nil
        routedPlayer = nil
        routedEngine = nil
        routedBuffers = []
        routedToken = UUID()
        completion = nil
    }

    private func speakRouted(
        _ text: String,
        device: AudioOutputDevice,
        rate: Float,
        completion: (@MainActor @Sendable () -> Void)?
    ) {
        let token = UUID()
        routedToken = token
        routedBuffers = []
        self.completion = completion

        let writer = AVSpeechSynthesizer()
        routedSynthesizer = writer
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.prefersAssistiveTechnologySettings = true
        writer.write(utterance) { [weak self] buffer in
            guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                return
            }
            let frameLength = pcmBuffer.frameLength
            let copiedBuffer = frameLength > 0 ? Self.copyBuffer(pcmBuffer).map { SendablePCMBuffer(buffer: $0) } : nil
            Task { @MainActor [weak self] in
                guard let self, self.routedToken == token else {
                    return
                }
                if frameLength == 0 {
                    self.playRoutedSpeech(text, deviceID: AudioDeviceID(device.id), rate: rate, token: token)
                } else if let copiedBuffer {
                    self.routedBuffers.append(copiedBuffer.buffer)
                }
            }
        }
    }

    private func playRoutedSpeech(
        _ text: String,
        deviceID: AudioDeviceID,
        rate: Float,
        token: UUID
    ) {
        guard !routedBuffers.isEmpty else {
            finishRoutedSpeech(token: token)
            return
        }

        let buffers = routedBuffers
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.outputNode, format: buffers[0].format)

        guard let audioUnit = engine.outputNode.audioUnit else {
            routedSynthesizer = nil
            routedBuffers = []
            speakWithSystemRoute(text, rate: rate, completion: completion)
            return
        }

        var routedDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &routedDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            routedSynthesizer = nil
            routedBuffers = []
            speakWithSystemRoute(text, rate: rate, completion: completion)
            return
        }

        do {
            try engine.start()
        } catch {
            routedSynthesizer = nil
            routedBuffers = []
            speakWithSystemRoute(text, rate: rate, completion: completion)
            return
        }

        routedEngine = engine
        routedPlayer = player
        routedBuffers = buffers
        for (index, buffer) in buffers.enumerated() {
            if index == buffers.count - 1 {
                player.scheduleBuffer(buffer) { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.finishRoutedSpeech(token: token)
                    }
                }
            } else {
                player.scheduleBuffer(buffer)
            }
        }
        player.play()
    }

    private func finishRoutedSpeech(token: UUID) {
        guard routedToken == token else {
            return
        }
        routedPlayer?.stop()
        routedEngine?.stop()
        routedSynthesizer = nil
        routedPlayer = nil
        routedEngine = nil
        routedBuffers = []
        completion?()
        completion = nil
    }

    nonisolated private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let copyBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in 0..<sourceBuffers.count {
            copyBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
            if let source = sourceBuffers[index].mData, let destination = copyBuffers[index].mData {
                memcpy(destination, source, Int(sourceBuffers[index].mDataByteSize))
            }
        }
        return copy
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
