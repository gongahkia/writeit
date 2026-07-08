import Foundation

public enum VLMBenchmarkInputMode: String, Codable, Sendable {
    case fixture
    case generatedRedacted = "generated_redacted"
    case liveScreen = "live_screen"
}

public struct VLMBenchmarkReport: Codable, Equatable, Sendable {
    public let tool: String
    public let startedAt: Date
    public let completedAt: Date
    public let provider: String
    public let modelID: String
    public let presetID: String
    public let prompt: String
    public let promptPolicy: String
    public let imageFixture: String
    public let imagePath: String
    public let inputMode: VLMBenchmarkInputMode
    public let maxTokens: Int
    public let timeoutSeconds: Double
    public let latencySeconds: Double
    public let success: Bool
    public let response: String
    public let error: String?
    public let responseMetadata: [String: String]

    public init(
        tool: String = "cerberus-vlm-benchmark",
        startedAt: Date,
        completedAt: Date,
        provider: String,
        modelID: String,
        presetID: String,
        prompt: String,
        promptPolicy: String = LocalVLMPromptPolicy.passiveScreenDescription,
        imageFixture: String,
        imagePath: String,
        inputMode: VLMBenchmarkInputMode,
        maxTokens: Int,
        timeoutSeconds: Double,
        latencySeconds: Double,
        success: Bool,
        response: String,
        error: String?,
        responseMetadata: [String: String]
    ) {
        self.tool = tool
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.provider = provider
        self.modelID = modelID
        self.presetID = presetID
        self.prompt = prompt
        self.promptPolicy = promptPolicy
        self.imageFixture = imageFixture
        self.imagePath = imagePath
        self.inputMode = inputMode
        self.maxTokens = max(1, maxTokens)
        self.timeoutSeconds = max(1, timeoutSeconds)
        self.latencySeconds = max(0, latencySeconds)
        self.success = success
        self.response = response
        self.error = error
        self.responseMetadata = responseMetadata
    }
}

public enum VLMBenchmarkRunner {
    public static func run(
        using provider: any LocalVLMProviding,
        presetID: String,
        prompt: String,
        imageURL: URL,
        imageFixture: String,
        inputMode: VLMBenchmarkInputMode,
        options: LocalVLMRequestOptions
    ) async -> VLMBenchmarkReport {
        let startedAt = Date()
        let latencyStart = Date()
        do {
            let response = try await LocalVLMProviderExecutor.answer(
                using: provider,
                imageURL: imageURL,
                prompt: LocalVLMPromptPolicy.passivePrompt(for: prompt),
                options: options
            )
            let completedAt = Date()
            return VLMBenchmarkReport(
                startedAt: startedAt,
                completedAt: completedAt,
                provider: provider.providerName,
                modelID: provider.modelID,
                presetID: presetID,
                prompt: prompt,
                imageFixture: imageFixture,
                imagePath: imageURL.path,
                inputMode: inputMode,
                maxTokens: options.maxTokens,
                timeoutSeconds: options.timeoutSeconds,
                latencySeconds: completedAt.timeIntervalSince(latencyStart),
                success: true,
                response: response.text,
                error: nil,
                responseMetadata: response.metadata
            )
        } catch {
            let completedAt = Date()
            return VLMBenchmarkReport(
                startedAt: startedAt,
                completedAt: completedAt,
                provider: provider.providerName,
                modelID: provider.modelID,
                presetID: presetID,
                prompt: prompt,
                imageFixture: imageFixture,
                imagePath: imageURL.path,
                inputMode: inputMode,
                maxTokens: options.maxTokens,
                timeoutSeconds: options.timeoutSeconds,
                latencySeconds: completedAt.timeIntervalSince(latencyStart),
                success: false,
                response: "",
                error: error.localizedDescription,
                responseMetadata: [:]
            )
        }
    }
}
