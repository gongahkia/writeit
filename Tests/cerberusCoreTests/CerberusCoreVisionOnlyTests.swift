import CoreGraphics
import Foundation
import Testing
@testable import cerberusCore

private struct FakeLocalVLMProvider: LocalVLMProviding {
    let providerName = "fake-vlm"
    let modelID = "fake-model"

    func answer(
        imageURL: URL,
        prompt: String,
        options: LocalVLMRequestOptions
    ) async throws -> LocalVLMResponse {
        LocalVLMResponse(
            text: "A visible test screen.",
            metadata: [
                "imageExists": "\(FileManager.default.fileExists(atPath: imageURL.path))",
                "maxTokens": "\(options.maxTokens)"
            ]
        )
    }
}

private actor RecordingHTTPTransport: LocalVLMHTTPTransport {
    struct Request: Sendable {
        let body: Data
        let url: URL
        let timeoutSeconds: Double
    }

    private let response: Data
    private var requests: [Request] = []

    init(response: String) {
        self.response = Data(response.utf8)
    }

    func postJSON(
        body: Data,
        to url: URL,
        timeoutSeconds: Double
    ) async throws -> Data {
        requests.append(Request(body: body, url: url, timeoutSeconds: timeoutSeconds))
        return response
    }

    func lastRequest() -> Request? {
        requests.last
    }
}

private struct FailingHTTPTransport: LocalVLMHTTPTransport {
    func postJSON(
        body: Data,
        to url: URL,
        timeoutSeconds: Double
    ) async throws -> Data {
        throw ToolExecutionError.denied("HTTP 500")
    }
}

@Test func defaultToolCatalogContainsOnlyScreenTools() {
    let names = DefaultToolCatalog.summaries.map(\.name)

    #expect(names == [
        "screen.barcodes",
        "screen.ocr",
        "screen.snapshot",
        "screen.ui_elements"
    ])
    #expect(DefaultToolCatalog.summaries.allSatisfy { !$0.mutatesState })
}

@Test func defaultNativeToolCatalogContainsOnlyScreenTools() {
    let names = DefaultToolCatalog.readOnlyFoundationModelTools().map(\.name).sorted()

    #expect(names == [
        "screen.barcodes",
        "screen.ocr",
        "screen.snapshot",
        "screen.ui_elements"
    ])
}

@Test func goldenRequestFixturesStayScreenOnly() throws {
    let fixtures = try loadGoldenRequestFixtures()
    let screenToolNames = Set(DefaultToolCatalog.summaries.map(\.name))

    #expect(!fixtures.isEmpty)
    #expect(fixtures.allSatisfy { Set($0.allowedToolNames).isSubset(of: screenToolNames) })
    #expect(fixtures.allSatisfy { $0.expectedToolName.isEmpty || screenToolNames.contains($0.expectedToolName) })
}

@Test func goldenRequestFixturesIncludeComputerUseRefusals() throws {
    let fixtures = try loadGoldenRequestFixtures()
    let refusalIDs = Set(fixtures.filter { $0.expectedIntent == "refuseUnsafeRequest" }.map(\.id))

    #expect(refusalIDs.isSuperset(of: [
        "refuse-click",
        "refuse-type",
        "refuse-open",
        "refuse-calendar-event",
        "refuse-reminder",
        "refuse-run",
        "refuse-shortcut",
        "refuse-search-files",
        "refuse-mcp"
    ]))
    #expect(fixtures
        .filter { $0.expectedIntent == "refuseUnsafeRequest" }
        .allSatisfy { $0.expectedToolName.isEmpty && !$0.expectedRequiresConfirmation })
}

@Test func localVLMPresetsCoverSupportedCandidates() {
    let ids = LocalVLMPreset.all.map(\.id)

    #expect(ids == [
        "minicpm-v-4.6",
        "qwen3-vl",
        "qwen2.5-vl",
        "smolvlm",
        "gemma-4",
        "internvl3.5",
        "fastvlm",
        "pixtral-12b"
    ])
    #expect(LocalVLMPreset.qwen3VL.safetyNote.lowercased().contains("passive"))
}

@Test func missingLocalVLMConfigurationLoadsDisabled() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent(LocalVLMConfiguration.fileName)

    let configuration = try LocalVLMConfiguration.load(from: fileURL)

    #expect(!configuration.enabled)
    #expect(configuration.statusLine == "Local VLM disabled")
}

@Test func localVLMConfigurationDecodesValidFile() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerberus-vlm-config-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directoryURL.appendingPathComponent(LocalVLMConfiguration.fileName)
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }
    let expected = LocalVLMConfiguration(
        enabled: true,
        provider: .ollama,
        presetID: "smolvlm",
        modelID: "smolvlm:latest",
        endpointURLString: "http://localhost:11434",
        maxTokens: 123,
        timeoutSeconds: 6
    )
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try JSONEncoder().encode(expected).write(to: fileURL)

    let decoded = try LocalVLMConfiguration.load(from: fileURL)

    #expect(decoded == expected)
}

@Test func localVLMEndpointPolicyRequiresLocalByDefault() throws {
    let localURL = try #require(URL(string: "http://127.0.0.1:11434"))
    let remoteURL = try #require(URL(string: "https://example.com/v1"))

    try LocalVLMEndpointPolicy.validate(localURL, allowNonLocalEndpoint: false)
    #expect(throws: ToolExecutionError.self) {
        try LocalVLMEndpointPolicy.validate(remoteURL, allowNonLocalEndpoint: false)
    }
    try LocalVLMEndpointPolicy.validate(remoteURL, allowNonLocalEndpoint: true)
}

@Test func localVLMFactoryBuildsOllamaProvider() throws {
    let configuration = LocalVLMConfiguration(
        enabled: true,
        provider: .ollama,
        modelID: "llava",
        endpointURLString: "http://localhost:11434"
    )

    let provider = try #require(try LocalVLMProviderFactory.provider(for: configuration))

    #expect(provider.providerName == "Ollama")
    #expect(provider.modelID == "llava")
}

@Test func invalidEnabledLocalVLMConfigurationFailsClosed() {
    let configuration = LocalVLMConfiguration(enabled: true, provider: .ollama, modelID: "")

    #expect(throws: ToolExecutionError.self) {
        try LocalVLMProviderFactory.provider(for: configuration)
    }
    #expect(!DefaultToolCatalog.makeTools(localVLMProvider: nil).map(\.name).contains("screen.describe"))
}

@Test func ollamaProviderSendsImageAndOptions() async throws {
    let imageURL = try TestImageFactory.writeImageData()
    defer {
        try? FileManager.default.removeItem(at: imageURL)
    }
    let transport = RecordingHTTPTransport(response: #"{"response":"ollama answer"}"#)
    let provider = OllamaVLMProvider(
        modelID: "llava",
        endpointURL: try #require(URL(string: "http://127.0.0.1:11434")),
        transport: transport
    )

    let response = try await provider.answer(
        imageURL: imageURL,
        prompt: "describe",
        options: LocalVLMRequestOptions(maxTokens: 9, timeoutSeconds: 4)
    )
    let request = try #require(await transport.lastRequest())
    let json = try TestImageFactory.jsonObject(from: request.body)
    let options = try #require(json["options"] as? [String: Any])
    let images = try #require(json["images"] as? [String])

    #expect(response.text == "ollama answer")
    #expect(request.url.absoluteString == "http://127.0.0.1:11434/api/generate")
    #expect(request.timeoutSeconds == 4)
    #expect(json["model"] as? String == "llava")
    #expect(json["prompt"] as? String == "describe")
    #expect(options["num_predict"] as? Int == 9)
    #expect(images.first?.isEmpty == false)
}

@Test func openAICompatibleProviderSendsVisionChatRequest() async throws {
    let imageURL = try TestImageFactory.writeImageData()
    defer {
        try? FileManager.default.removeItem(at: imageURL)
    }
    let transport = RecordingHTTPTransport(response: #"{"choices":[{"message":{"content":"chat answer"}}]}"#)
    let provider = OpenAICompatibleVLMProvider(
        providerName: "llama.cpp",
        modelID: "vision-model",
        endpointURL: try #require(URL(string: "http://localhost:8080/v1")),
        transport: transport
    )

    let response = try await provider.answer(
        imageURL: imageURL,
        prompt: "what is visible?",
        options: LocalVLMRequestOptions(maxTokens: 11, timeoutSeconds: 5)
    )
    let request = try #require(await transport.lastRequest())
    let json = try TestImageFactory.jsonObject(from: request.body)
    let messages = try #require(json["messages"] as? [[String: Any]])
    let firstMessage = try #require(messages.first)
    let content = try #require(firstMessage["content"] as? [[String: Any]])

    #expect(response.text == "chat answer")
    #expect(request.url.absoluteString == "http://localhost:8080/v1/chat/completions")
    #expect(json["model"] as? String == "vision-model")
    #expect(json["max_tokens"] as? Int == 11)
    #expect(content.contains { $0["type"] as? String == "text" })
    #expect(content.contains { $0["type"] as? String == "image_url" })
}

@Test func openAICompatibleProviderPropagatesTransportFailure() async throws {
    let imageURL = try TestImageFactory.writeImageData()
    defer {
        try? FileManager.default.removeItem(at: imageURL)
    }
    let provider = OpenAICompatibleVLMProvider(
        providerName: "local",
        modelID: "vision-model",
        endpointURL: try #require(URL(string: "http://localhost:8080")),
        transport: FailingHTTPTransport()
    )

    await #expect(throws: ToolExecutionError.self) {
        try await provider.answer(
            imageURL: imageURL,
            prompt: "describe",
            options: LocalVLMRequestOptions(maxTokens: 8, timeoutSeconds: 1)
        )
    }
}

@Test func ollamaProviderPropagatesTransportFailure() async throws {
    let imageURL = try TestImageFactory.writeImageData()
    defer {
        try? FileManager.default.removeItem(at: imageURL)
    }
    let provider = OllamaVLMProvider(
        modelID: "llava",
        endpointURL: try #require(URL(string: "http://localhost:11434")),
        transport: FailingHTTPTransport()
    )

    await #expect(throws: ToolExecutionError.self) {
        try await provider.answer(
            imageURL: imageURL,
            prompt: "describe",
            options: LocalVLMRequestOptions(maxTokens: 8, timeoutSeconds: 1)
        )
    }
}

@Test func openAICompatibleProviderRejectsMalformedResponse() async throws {
    let imageURL = try TestImageFactory.writeImageData()
    defer {
        try? FileManager.default.removeItem(at: imageURL)
    }
    let provider = OpenAICompatibleVLMProvider(
        providerName: "local",
        modelID: "vision-model",
        endpointURL: try #require(URL(string: "http://localhost:8080")),
        transport: RecordingHTTPTransport(response: #"{"choices":[]}"#)
    )

    await #expect(throws: ToolExecutionError.self) {
        try await provider.answer(
            imageURL: imageURL,
            prompt: "describe",
            options: LocalVLMRequestOptions(maxTokens: 8, timeoutSeconds: 1)
        )
    }
}

@Test func localVLMSubprocessProviderRunsCommand() async throws {
    let provider = LocalVLMSubprocessProvider(
        providerName: "MLX-VLM",
        modelID: "sub-model",
        executableURL: URL(fileURLWithPath: "/bin/echo"),
        arguments: ["answer", "{model}", "{maxTokens}"]
    )

    let response = try await provider.answer(
        imageURL: URL(fileURLWithPath: "/tmp/no-image.png"),
        prompt: "describe",
        options: LocalVLMRequestOptions(maxTokens: 7, timeoutSeconds: 2)
    )

    #expect(response.text == "answer sub-model 7")
}

@Test func localVLMSubprocessProviderReportsFailure() async {
    let provider = LocalVLMSubprocessProvider(
        providerName: "MLX-VLM",
        modelID: "sub-model",
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "echo failed >&2; exit 3"]
    )

    await #expect(throws: ToolExecutionError.self) {
        try await provider.answer(
            imageURL: URL(fileURLWithPath: "/tmp/no-image.png"),
            prompt: "describe",
            options: LocalVLMRequestOptions(maxTokens: 7, timeoutSeconds: 2)
        )
    }
}

@Test func localVLMSubprocessProviderTimesOut() async {
    let provider = LocalVLMSubprocessProvider(
        providerName: "MLX-VLM",
        modelID: "sub-model",
        executableURL: URL(fileURLWithPath: "/bin/sleep"),
        arguments: ["2"]
    )

    await #expect(throws: ToolExecutionError.self) {
        try await provider.answer(
            imageURL: URL(fileURLWithPath: "/tmp/no-image.png"),
            prompt: "describe",
            options: LocalVLMRequestOptions(maxTokens: 7, timeoutSeconds: 1)
        )
    }
}

@Test func localVLMCatalogRegistrationIsOptional() {
    let defaultNames = DefaultToolCatalog.summaries.map(\.name)
    let providerNames = DefaultToolCatalog
        .makeTools(localVLMProvider: FakeLocalVLMProvider())
        .map(\.name)
        .sorted()
    let nativeNames = DefaultToolCatalog
        .readOnlyFoundationModelTools(localVLMProvider: FakeLocalVLMProvider())
        .map(\.name)
        .sorted()

    #expect(!defaultNames.contains("screen.describe"))
    #expect(providerNames.contains("screen.describe"))
    #expect(nativeNames.contains("screen.describe"))
}

@Test func screenDescribeValidatesPrompt() {
    let tool = ScreenDescribeTool(provider: FakeLocalVLMProvider())

    #expect(throws: ToolExecutionError.self) {
        try tool.validate(ScreenDescribeTool.Arguments(prompt: " "))
    }
}

@Test func screenDescribeRunsConfiguredLocalVLM() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerberus-vlm-test-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }
    let image = try #require(TestImageFactory.makeTestImage())
    let tool = ScreenDescribeTool(
        provider: FakeLocalVLMProvider(),
        options: LocalVLMRequestOptions(maxTokens: 42, timeoutSeconds: 2),
        outputDirectoryURL: directoryURL,
        cachePolicy: ScreenSnapshotCachePolicy(maximumFileCount: 2, maximumAge: 60),
        hasScreenCaptureAccess: { true },
        captureImage: { scope in
            CapturedScreenImage(image: image, scope: scope, sourceDescription: "test screen")
        }
    )

    let result = try await tool.run(arguments: ScreenDescribeTool.Arguments(prompt: "what is visible?"))
    let imagePath = try #require(result.metadata["imagePath"])

    #expect(result.spokenSummary == "A visible test screen.")
    #expect(result.metadata["provider"] == "fake-vlm")
    #expect(result.metadata["modelID"] == "fake-model")
    #expect(result.metadata["imageExists"] == "true")
    #expect(result.metadata["maxTokens"] == "42")
    #expect(FileManager.default.fileExists(atPath: imagePath))
}

@Test func toolProfileIsVisionOnly() {
    let configuration = ToolProfile.visionOnly.configuration(ambientSummaries: DefaultToolCatalog.summaries)

    #expect(ToolProfile.allCases == [.visionOnly])
    #expect(ToolProfile.profile(id: "unknown") == .visionOnly)
    #expect(configuration.disabledAmbientToolNames.isEmpty)
    #expect(!configuration.requiresConfirmationForAllTools)
}

@Test func toolEnablementFiltersOnlyAmbientScreenTools() {
    var allowlist = ToolSessionAllowlist()
    allowlist.setEnabled("screen.ocr", enabled: false)

    let names = ToolEnablementPolicy(ambientAllowlist: allowlist)
        .enabledSummaries(ambientSummaries: DefaultToolCatalog.summaries)
        .map(\.name)

    #expect(names == [
        "screen.barcodes",
        "screen.snapshot",
        "screen.ui_elements"
    ])
}

@Test func systemPromptRefusesComputerUse() {
    let prompt = SystemPrompt.render(toolSummaries: DefaultToolCatalog.summaries)
    func toolName(_ lhs: String, _ rhs: String) -> String {
        "\(lhs).\(rhs)"
    }

    #expect(prompt.contains("screen-reading assistant"))
    #expect(prompt.contains("Never claim that you opened apps, clicked, typed"))
    #expect(prompt.contains("Refuse requests that require operating the computer"))
    #expect(!prompt.contains(toolName("shell", "run")))
    #expect(!prompt.contains(toolName("mcp", "call")))
    #expect(!prompt.contains(toolName("app", "control")))
}

@Test func assistantContextExposesOnlyScreenToolContext() {
    let context = AssistantContext(
        activeApplicationName: "Xcode",
        allowedToolNames: DefaultToolCatalog.summaries.map(\.name),
        activeApplicationHints: ["Use screen reads only; never operate the app."]
    )

    #expect(context.promptFragment.contains("Active app: Xcode"))
    #expect(context.promptFragment.contains("Allowed tools: screen.barcodes, screen.ocr, screen.snapshot, screen.ui_elements"))
    #expect(!context.promptFragment.contains("File search folders"))
}

@Test func screenSnapshotPayloadPointsBackToScreenTools() {
    let payload = ScreenSnapshotTool.payload(
        fileURL: URL(fileURLWithPath: "/tmp/screen.png"),
        imageSize: CGSize(width: 1200, height: 800)
    )

    #expect(payload.contains("screen.ocr"))
    #expect(payload.contains("1200x800"))
}

@Test func forbiddenComputerUseToolNamesAreAbsent() {
    func name(_ parts: String...) -> String {
        parts.joined(separator: ".")
    }

    let forbidden = [
        name("app", "control"),
        name("browser", "open_url"),
        name("browser", "tabs"),
        name("calendar", "read"),
        name("contacts", "search"),
        name("files", "search"),
        name("finder", "reveal"),
        name("mail", "search"),
        name("mcp", "call"),
        name("memory", "write"),
        name("music", "control"),
        name("notes", "search"),
        name("reminders", "create"),
        name("shell", "run"),
        name("shortcuts", "run"),
        name("web", "search")
    ]
    let names = Set(DefaultToolCatalog.summaries.map(\.name))

    #expect(forbidden.allSatisfy { !names.contains($0) })
}

private enum TestImageFactory {
    static func makeTestImage() -> CGImage? {
        let pixel = Data([0, 0, 0, 255])
        guard let provider = CGDataProvider(data: pixel as CFData) else {
            return nil
        }
        return CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    static func writeImageData() throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cerberus-vlm-image-\(UUID().uuidString).png")
        try Data([0, 1, 2, 3]).write(to: fileURL)
        return fileURL
    }

    static func jsonObject(from data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private func loadGoldenRequestFixtures() throws -> [GoldenRequestFixture] {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Fixtures/Model/golden-requests.jsonl")
    return try GoldenRequestFixtures.parseJSONL(Data(contentsOf: url))
}
