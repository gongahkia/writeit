import AVFoundation
import Foundation

public enum AudioBufferConversionError: Error, LocalizedError {
    case cannotCreateConverter
    case cannotCreateOutputBuffer
    case conversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cannotCreateConverter:
            "Could not create an audio converter for the microphone format."
        case .cannotCreateOutputBuffer:
            "Could not allocate a converted audio buffer."
        case .conversionFailed(let message):
            "Audio conversion failed: \(message)"
        }
    }
}

public enum AudioBufferConverter {
    public static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard !buffer.format.isEqual(format) else {
            return buffer
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            throw AudioBufferConversionError.cannotCreateConverter
        }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            throw AudioBufferConversionError.cannotCreateOutputBuffer
        }

        var didProvideInput = false
        var conversionError: NSError?

        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error {
            throw AudioBufferConversionError.conversionFailed(
                conversionError?.localizedDescription ?? "unknown error"
            )
        }

        return convertedBuffer
    }
}
