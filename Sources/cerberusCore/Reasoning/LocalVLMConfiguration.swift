import Foundation

public enum LocalVLMProviderKind: String, Codable, CaseIterable, Sendable {
    case mlxVLM = "mlx_vlm"
    case ollama
    case llamaCPP = "llama_cpp"
    case openAICompatible = "openai_compatible"

    public var displayName: String {
        switch self {
        case .mlxVLM:
            "MLX-VLM"
        case .ollama:
            "Ollama"
        case .llamaCPP:
            "llama.cpp"
        case .openAICompatible:
            "OpenAI-compatible"
        }
    }
}

public struct LocalVLMConfiguration: Codable, Equatable, Sendable {
    public static let fileName = "local-vlm.json"

    public let enabled: Bool
    public let provider: LocalVLMProviderKind
    public let presetID: String
    public let modelID: String
    public let endpointURLString: String?
    public let executablePath: String?
    public let arguments: [String]
    public let maxTokens: Int
    public let timeoutSeconds: Double
    public let allowNonLocalEndpoint: Bool

    public init(
        enabled: Bool = false,
        provider: LocalVLMProviderKind = .mlxVLM,
        presetID: String = LocalVLMPreset.miniCPMV46.id,
        modelID: String = "",
        endpointURLString: String? = nil,
        executablePath: String? = nil,
        arguments: [String] = [],
        maxTokens: Int = 256,
        timeoutSeconds: Double = 45,
        allowNonLocalEndpoint: Bool = false
    ) {
        self.enabled = enabled
        self.provider = provider
        self.presetID = presetID
        self.modelID = modelID
        self.endpointURLString = endpointURLString
        self.executablePath = executablePath
        self.arguments = arguments
        self.maxTokens = max(1, maxTokens)
        self.timeoutSeconds = max(1, timeoutSeconds)
        self.allowNonLocalEndpoint = allowNonLocalEndpoint
    }

    public static let disabled = LocalVLMConfiguration()

    public var statusLine: String {
        guard enabled else {
            return "Local VLM disabled; configure local-vlm.json to enable screen.describe"
        }
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty
            ? "\(provider.displayName) enabled without a model id"
            : "\(provider.displayName): \(model)"
    }

    public var requestOptions: LocalVLMRequestOptions {
        LocalVLMRequestOptions(maxTokens: maxTokens, timeoutSeconds: timeoutSeconds)
    }

    public static func defaultFileURL() -> URL {
        CerberusDirectories.applicationSupportFile(fileName)
    }

    public static func load(from fileURL: URL = defaultFileURL()) throws -> LocalVLMConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .disabled
        }
        return try JSONDecoder().decode(LocalVLMConfiguration.self, from: Data(contentsOf: fileURL))
    }
}
