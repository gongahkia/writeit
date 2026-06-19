import Foundation

public enum WakeWordMonitorStatusLine {
    public static let speechTranscription = "Wake phrase uses speech transcription"
    public static let soundModelConfigured = "Sound wake model configured"
    public static let soundModelConfigMissing = "Sound wake model config missing"
    public static let soundModelConfigMissingUsingSpeechPhrase = "Sound wake model config not found; using speech phrase"
    public static let soundModelArmed = "Sound wake model armed"
    public static let soundMatched = "Sound wake matched"

    public static func soundMatched(identifier: String, confidence: Double) -> String {
        "\(soundMatched) \(identifier) \(Int(confidence * 100))%"
    }
}
