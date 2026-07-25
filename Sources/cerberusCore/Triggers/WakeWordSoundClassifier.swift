import AVFoundation
import CoreML
import CoreMedia
import Foundation
@preconcurrency import SoundAnalysis

public struct WakeWordSoundClassifierConfiguration: Codable, Equatable, Sendable {
    public enum ComputeUnits: String, Codable, Sendable {
        case all
        case cpuAndGPU
        case cpuOnly
        case cpuAndNeuralEngine
    }

    public let modelPath: String
    public let targetLabels: [String]
    public let confidenceThreshold: Double
    public let overlapFactor: Double
    public let windowDurationSeconds: Double?
    public let computeUnits: ComputeUnits

    public init(
        modelPath: String,
        targetLabels: [String],
        confidenceThreshold: Double = 0.85,
        overlapFactor: Double = 0.5,
        windowDurationSeconds: Double? = nil,
        computeUnits: ComputeUnits = .cpuAndNeuralEngine
    ) {
        self.modelPath = modelPath
        self.targetLabels = targetLabels
        self.confidenceThreshold = confidenceThreshold
        self.overlapFactor = overlapFactor
        self.windowDurationSeconds = windowDurationSeconds
        self.computeUnits = computeUnits
    }

    public var normalizedTargetLabels: Set<String> {
        Set(targetLabels.map(Self.normalizeLabel).filter { !$0.isEmpty })
    }

    public func validate() throws {
        guard !modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WakeWordSoundClassifierError.invalidConfiguration("modelPath is required.")
        }
        guard !normalizedTargetLabels.isEmpty else {
            throw WakeWordSoundClassifierError.invalidConfiguration("targetLabels must contain at least one label.")
        }
        guard confidenceThreshold > 0, confidenceThreshold <= 1 else {
            throw WakeWordSoundClassifierError.invalidConfiguration("confidenceThreshold must be in (0, 1].")
        }
        guard overlapFactor >= 0, overlapFactor < 1 else {
            throw WakeWordSoundClassifierError.invalidConfiguration("overlapFactor must be in [0, 1).")
        }
        if let windowDurationSeconds, windowDurationSeconds <= 0 {
            throw WakeWordSoundClassifierError.invalidConfiguration("windowDurationSeconds must be positive.")
        }
    }

    static func normalizeLabel(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct WakeWordSoundClassification: Equatable, Sendable {
    public let identifier: String
    public let confidence: Double

    public init(identifier: String, confidence: Double) {
        self.identifier = identifier
        self.confidence = confidence
    }
}

public enum WakeWordSoundClassifierError: Error, Equatable, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case configurationNotFound(URL)
    case unsupportedModelType(URL)
    case noCompatibleAudioFormat

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            message
        case let .configurationNotFound(url):
            "Wake word sound classifier config not found: \(url.path)"
        case let .unsupportedModelType(url):
            "Wake word model must be .mlmodel or .mlmodelc: \(url.path)"
        case .noCompatibleAudioFormat:
            "Wake word sound classifier could not find a compatible microphone format."
        }
    }
}

public enum WakeWordSoundClassifierConfigurationLoader {
    public static func loadIfPresent(fileURL: URL = defaultFileURL()) throws -> WakeWordSoundClassifierConfiguration? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        let configuration = try JSONDecoder().decode(WakeWordSoundClassifierConfiguration.self, from: data)
        try configuration.validate()
        return configuration
    }

    public static func defaultFileURL() -> URL {
        CerberusDirectories.applicationSupportFile("wake-word-sound-classifier.json")
    }
}

private final class WakeWordSoundObserver: NSObject, SNResultsObserving {
    private let targetLabels: Set<String>
    private let confidenceThreshold: Double
    private let onDetection: @Sendable ([WakeWordSoundClassification]) -> Void

    init(
        targetLabels: Set<String>,
        confidenceThreshold: Double,
        onDetection: @escaping @Sendable ([WakeWordSoundClassification]) -> Void
    ) {
        self.targetLabels = targetLabels
        self.confidenceThreshold = confidenceThreshold
        self.onDetection = onDetection
    }

    func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let result = result as? SNClassificationResult else {
            return
        }

        let matches = result.classifications.compactMap { classification -> WakeWordSoundClassification? in
            let normalizedLabel = WakeWordSoundClassifierConfiguration.normalizeLabel(classification.identifier)
            guard targetLabels.contains(normalizedLabel), classification.confidence >= confidenceThreshold else {
                return nil
            }
            return WakeWordSoundClassification(
                identifier: classification.identifier,
                confidence: classification.confidence
            )
        }

        guard !matches.isEmpty else {
            return
        }
        onDetection(matches)
    }

    func request(_ request: any SNRequest, didFailWithError error: any Error) {}

    func requestDidComplete(_ request: any SNRequest) {}
}

private final class WakeWordAudioStreamFeeder: @unchecked Sendable {
    private let analyzer: SNAudioStreamAnalyzer
    private var framePosition: AVAudioFramePosition = 0

    init(analyzer: SNAudioStreamAnalyzer) {
        self.analyzer = analyzer
    }

    func analyze(_ buffer: AVAudioPCMBuffer) {
        analyzer.analyze(buffer, atAudioFramePosition: framePosition)
        framePosition += AVAudioFramePosition(buffer.frameLength)
    }

    func complete() {
        analyzer.completeAnalysis()
        analyzer.removeAllRequests()
    }
}

@MainActor
public final class WakeWordSoundClassifier {
    private let audioEngine = AVAudioEngine()
    private var feeder: WakeWordAudioStreamFeeder?
    private var observer: WakeWordSoundObserver?

    public private(set) var isRunning = false

    public init() {}

    public func start(
        configuration: WakeWordSoundClassifierConfiguration,
        onDetection: @escaping @MainActor @Sendable ([WakeWordSoundClassification]) -> Void
    ) async throws {
        guard !isRunning else {
            return
        }
        try configuration.validate()

        let modelURL = try await modelURL(for: configuration)
        let modelConfiguration = MLModelConfiguration()
        modelConfiguration.computeUnits = configuration.computeUnits.mlComputeUnits
        let model = try await MLModel.load(contentsOf: modelURL, configuration: modelConfiguration)
        let request = try SNClassifySoundRequest(mlModel: model)
        request.overlapFactor = configuration.overlapFactor
        if let windowDurationSeconds = configuration.windowDurationSeconds {
            request.windowDuration = CMTime(seconds: windowDurationSeconds, preferredTimescale: 600)
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.commonFormat == .pcmFormatFloat32 || inputFormat.commonFormat == .pcmFormatInt16 else {
            throw WakeWordSoundClassifierError.noCompatibleAudioFormat
        }

        let analyzer = SNAudioStreamAnalyzer(format: inputFormat)
        let observer = WakeWordSoundObserver(
            targetLabels: configuration.normalizedTargetLabels,
            confidenceThreshold: configuration.confidenceThreshold
        ) { classifications in
            Task { @MainActor in
                onDetection(classifications)
            }
        }
        try analyzer.add(request, withObserver: observer)

        let feeder = WakeWordAudioStreamFeeder(analyzer: analyzer)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 8192, format: inputFormat) { buffer, _ in
            feeder.analyze(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        self.feeder = feeder
        self.observer = observer
        isRunning = true
    }

    public func cancel() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        feeder?.complete()
        feeder = nil
        observer = nil
        isRunning = false
    }

    private func modelURL(for configuration: WakeWordSoundClassifierConfiguration) async throws -> URL {
        let fileURL = URL(fileURLWithPath: configuration.modelPath)
        switch fileURL.pathExtension {
        case "mlmodelc":
            return fileURL
        case "mlmodel":
            return try await MLModel.compileModel(at: fileURL)
        default:
            throw WakeWordSoundClassifierError.unsupportedModelType(fileURL)
        }
    }
}

private extension WakeWordSoundClassifierConfiguration.ComputeUnits {
    var mlComputeUnits: MLComputeUnits {
        switch self {
        case .all:
            .all
        case .cpuAndGPU:
            .cpuAndGPU
        case .cpuOnly:
            .cpuOnly
        case .cpuAndNeuralEngine:
            .cpuAndNeuralEngine
        }
    }
}
