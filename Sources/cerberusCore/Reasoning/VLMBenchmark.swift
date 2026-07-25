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

public struct VLMGoldenFixture: Codable, Equatable, Sendable {
    public let id: String
    public let imagePath: String
    public let prompt: String
    public let answerRubric: String
    public let requiredSignals: [String]
    public let forbiddenSignals: [String]

    public init(
        id: String,
        imagePath: String,
        prompt: String,
        answerRubric: String,
        requiredSignals: [String],
        forbiddenSignals: [String] = []
    ) {
        self.id = id
        self.imagePath = imagePath
        self.prompt = prompt
        self.answerRubric = answerRubric
        self.requiredSignals = requiredSignals
        self.forbiddenSignals = forbiddenSignals
    }
}

public struct VLMGoldenFixtureResult: Codable, Equatable, Sendable {
    public let id: String
    public let imagePath: String
    public let prompt: String
    public let passed: Bool
    public let providerSucceeded: Bool
    public let latencySeconds: Double
    public let response: String
    public let error: String?
    public let matchedRequiredSignals: [String]
    public let missingRequiredSignals: [String]
    public let presentForbiddenSignals: [String]

    public init(fixture: VLMGoldenFixture, report: VLMBenchmarkReport) {
        let response = report.response.lowercased()
        let matched = fixture.requiredSignals.filter { response.contains($0.lowercased()) }
        let missing = fixture.requiredSignals.filter { !response.contains($0.lowercased()) }
        let presentForbidden = fixture.forbiddenSignals.filter { response.contains($0.lowercased()) }

        id = fixture.id
        imagePath = fixture.imagePath
        prompt = fixture.prompt
        providerSucceeded = report.success
        latencySeconds = report.latencySeconds
        self.response = report.response
        error = report.error
        matchedRequiredSignals = matched
        missingRequiredSignals = missing
        presentForbiddenSignals = presentForbidden
        passed = report.success && missing.isEmpty && presentForbidden.isEmpty
    }
}

public struct VLMGoldenEvaluationReport: Codable, Equatable, Sendable {
    public let tool: String
    public let startedAt: Date
    public let completedAt: Date
    public let provider: String
    public let modelID: String
    public let presetID: String
    public let totalCount: Int
    public let passedCount: Int
    public let results: [VLMGoldenFixtureResult]

    public init(
        tool: String = "cerberus-vlm-golden-eval",
        startedAt: Date,
        completedAt: Date,
        provider: String,
        modelID: String,
        presetID: String,
        results: [VLMGoldenFixtureResult]
    ) {
        self.tool = tool
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.provider = provider
        self.modelID = modelID
        self.presetID = presetID
        totalCount = results.count
        passedCount = results.filter(\.passed).count
        self.results = results
    }
}

public enum VLMGoldenFixtures {
    public static func load(from fileURL: URL) throws -> [VLMGoldenFixture] {
        let data = try Data(contentsOf: fileURL)
        let fixtures = try JSONDecoder().decode([VLMGoldenFixture].self, from: data)
        try validate(fixtures)
        return fixtures
    }

    public static func validate(_ fixtures: [VLMGoldenFixture]) throws {
        guard !fixtures.isEmpty else {
            throw ToolExecutionError.invalidArguments("VLM golden fixtures must not be empty.")
        }
        var ids = Set<String>()
        for fixture in fixtures {
            let trimmedID = fixture.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else {
                throw ToolExecutionError.invalidArguments("VLM golden fixture id is required.")
            }
            guard ids.insert(trimmedID).inserted else {
                throw ToolExecutionError.invalidArguments("Duplicate VLM golden fixture id: \(trimmedID)")
            }
            guard !fixture.imagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ToolExecutionError.invalidArguments("VLM golden fixture \(trimmedID) requires imagePath.")
            }
            guard !fixture.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ToolExecutionError.invalidArguments("VLM golden fixture \(trimmedID) requires prompt.")
            }
            guard !fixture.requiredSignals.isEmpty else {
                throw ToolExecutionError.invalidArguments("VLM golden fixture \(trimmedID) requires requiredSignals.")
            }
        }
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
