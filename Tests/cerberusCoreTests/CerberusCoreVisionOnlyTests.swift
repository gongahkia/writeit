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

private actor PromptRecorder {
    private var prompts: [String] = []

    func record(_ prompt: String) {
        prompts.append(prompt)
    }

    func lastPrompt() -> String? {
        prompts.last
    }
}

private struct RecordingPromptLocalVLMProvider: LocalVLMProviding {
    let providerName = "recording-vlm"
    let modelID = "qwen3-vl-test"
    let recorder: PromptRecorder

    func answer(
        imageURL: URL,
        prompt: String,
        options: LocalVLMRequestOptions
    ) async throws -> LocalVLMResponse {
        await recorder.record(prompt)
        return LocalVLMResponse(text: "I can describe the UI, but I cannot operate it.")
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

private final class MockURLProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var statusCode = 200
    private var body = Data()

    func set(statusCode: Int, body: String) {
        lock.lock()
        self.statusCode = statusCode
        self.body = Data(body.utf8)
        lock.unlock()
    }

    func snapshot() -> (statusCode: Int, body: Data) {
        lock.lock()
        defer {
            lock.unlock()
        }
        return (statusCode, body)
    }
}

private final class MockURLProtocol: URLProtocol {
    static let state = MockURLProtocolState()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let snapshot = Self.state.snapshot()
        let response = HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"),
            statusCode: snapshot.statusCode,
            httpVersion: nil,
            headerFields: nil
        )
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: snapshot.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct DelayedLocalVLMProvider: LocalVLMProviding {
    let providerName = "delayed-vlm"
    let modelID = "delayed-model"
    let delayNanoseconds: UInt64

    func answer(
        imageURL: URL,
        prompt: String,
        options: LocalVLMRequestOptions
    ) async throws -> LocalVLMResponse {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return LocalVLMResponse(text: "delayed answer")
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
    let screenToolNames = Set(DefaultToolCatalog.makeTools(localVLMProvider: FakeLocalVLMProvider()).map(\.name))

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
        "refuse-mail-search",
        "refuse-contact-search",
        "refuse-note-search",
        "refuse-music-control",
        "refuse-search-files",
        "refuse-web-search",
        "refuse-memory-write",
        "refuse-memory-read",
        "refuse-mcp",
        "refuse-mcp-list",
        "refuse-mcp-prompt",
        "refuse-vlm-click",
        "refuse-vlm-operate-ui"
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
    #expect(LocalVLMPreset.miniCPMV46.licenseNote.contains("2026-07-08"))
    #expect(LocalVLMPreset.miniCPMV46.licenseNote.contains("https://huggingface.co/openbmb/MiniCPM-V-4.6"))
    #expect(LocalVLMPreset.miniCPMV46.runtimeNotes.contains("Config-only preset; no weights bundled."))
    #expect(LocalVLMPreset.qwen3VL.licenseNote.contains("2026-07-08"))
    #expect(LocalVLMPreset.qwen3VL.runtimeNotes.contains("Supported sizes checked: 2B, 4B, 8B, 30B-A3B, 32B, and 235B-A22B."))
    #expect(LocalVLMPreset.qwen3VL.safetyNote.lowercased().contains("passive"))
    #expect(LocalVLMPreset.qwen25VL.licenseNote.contains("2026-07-08"))
    #expect(LocalVLMPreset.qwen25VL.runtimeNotes.contains("Expected strengths: OCR, documents, charts, layout, and UI screenshots."))
    #expect(LocalVLMPreset.smolVLM.licenseNote.contains("2026-07-08"))
    #expect(LocalVLMPreset.smolVLM.recommendedMaxTokens == 128)
    #expect(LocalVLMPreset.smolVLM.recommendedTimeoutSeconds == 30)
    #expect(LocalVLMPreset.smolVLM.runtimeNotes.contains("Low-resource fallback for users who cannot run MiniCPM, Qwen, or InternVL."))
}

@Test func miniCPMV46BenchmarkTemplateCoversRequiredCases() throws {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Fixtures/VLM/benchmark-template.json")
    let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let cases = try #require(json["cases"] as? [[String: Any]])
    let caseIDs = Set(cases.compactMap { $0["id"] as? String })
    let comparisonPresetIDs = try #require(json["comparisonPresetIDs"] as? [String])

    #expect(json["presetID"] as? String == LocalVLMPreset.miniCPMV46.id)
    #expect(json["modelID"] as? String == "openbmb/MiniCPM-V-4.6")
    #expect(json["sourceCheckedDate"] as? String == "2026-07-08")
    #expect(json["weightsBundled"] as? Bool == false)
    #expect(comparisonPresetIDs == [
        "minicpm-v-4.6",
        "qwen3-vl",
        "qwen2.5-vl",
        "smolvlm"
    ])
    #expect(caseIDs == [
        "ui-screenshot",
        "dense-text",
        "chart",
        "code-editor",
        "qr-barcode",
        "low-light-image"
    ])
}

@Test func missingLocalVLMConfigurationLoadsDisabled() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent(LocalVLMConfiguration.fileName)

    let configuration = try LocalVLMConfiguration.load(from: fileURL)

    #expect(!configuration.enabled)
    #expect(configuration.statusLine == "Local VLM disabled; configure local-vlm.json to enable screen.describe")
}

@Test func localVLMConfigurationDefaultStateIsDisabled() {
    let configuration = LocalVLMConfiguration.disabled

    #expect(!configuration.enabled)
    #expect(configuration.provider == .mlxVLM)
    #expect(configuration.presetID == LocalVLMPreset.miniCPMV46.id)
    #expect(configuration.modelID.isEmpty)
    #expect(configuration.endpointURLString == nil)
    #expect(configuration.executablePath == nil)
    #expect(configuration.arguments.isEmpty)
    #expect(configuration.maxTokens == 256)
    #expect(configuration.timeoutSeconds == 45)
    #expect(!configuration.allowNonLocalEndpoint)
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

@Test func invalidLocalVLMConfigurationFileFailsClosed() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerberus-vlm-invalid-config-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directoryURL.appendingPathComponent(LocalVLMConfiguration.fileName)
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try #"{"enabled":true,"provider":"network_api","presetID":"smolvlm","modelID":"x","arguments":[],"maxTokens":256,"timeoutSeconds":45,"allowNonLocalEndpoint":false}"#
        .write(to: fileURL, atomically: true, encoding: .utf8)

    #expect(throws: DecodingError.self) {
        _ = try LocalVLMConfiguration.load(from: fileURL)
    }
    #expect(!DefaultToolCatalog.makeTools(localVLMProvider: nil).map(\.name).contains("screen.describe"))
}

@Test func localVLMEndpointPolicyRequiresHTTPAndLocalByDefault() throws {
    let localURL = try #require(URL(string: "http://127.0.0.1:11434"))
    let remoteURL = try #require(URL(string: "https://example.com/v1"))
    let fileURL = URL(fileURLWithPath: "/tmp/vlm.sock")

    try LocalVLMEndpointPolicy.validate(localURL, allowNonLocalEndpoint: false)
    #expect(throws: ToolExecutionError.self) {
        try LocalVLMEndpointPolicy.validate(remoteURL, allowNonLocalEndpoint: false)
    }
    try LocalVLMEndpointPolicy.validate(remoteURL, allowNonLocalEndpoint: true)
    #expect(throws: ToolExecutionError.self) {
        try LocalVLMEndpointPolicy.validate(fileURL, allowNonLocalEndpoint: true)
    }
}

@Test func localVLMFactoryBuildsOllamaProvider() throws {
    let configuration = LocalVLMConfiguration(
        enabled: true,
        provider: .ollama,
        modelID: "llava"
    )

    let anyProvider = try #require(try LocalVLMProviderFactory.provider(for: configuration))
    let provider = try #require(anyProvider as? OllamaVLMProvider)

    #expect(provider.providerName == "Ollama")
    #expect(provider.modelID == "llava")
    #expect(provider.endpointURL.absoluteString == "http://127.0.0.1:11434")
}

@Test func localVLMFactoryRejectsRemoteOllamaEndpointByDefault() {
    let configuration = LocalVLMConfiguration(
        enabled: true,
        provider: .ollama,
        modelID: "llava",
        endpointURLString: "https://example.com"
    )

    #expect(throws: ToolExecutionError.self) {
        try LocalVLMProviderFactory.provider(for: configuration)
    }
}

@Test func localVLMFactoryBuildsLlamaCPPProvider() throws {
    let configuration = LocalVLMConfiguration(
        enabled: true,
        provider: .llamaCPP,
        modelID: "vision.gguf"
    )

    let anyProvider = try #require(try LocalVLMProviderFactory.provider(for: configuration))
    let provider = try #require(anyProvider as? OpenAICompatibleVLMProvider)

    #expect(provider.providerName == "llama.cpp")
    #expect(provider.modelID == "vision.gguf")
    #expect(provider.endpointURL.absoluteString == "http://127.0.0.1:8080")
}

@Test func localVLMFactoryRejectsRemoteLlamaCPPEndpointByDefault() {
    let configuration = LocalVLMConfiguration(
        enabled: true,
        provider: .llamaCPP,
        modelID: "vision.gguf",
        endpointURLString: "https://example.com/v1"
    )

    #expect(throws: ToolExecutionError.self) {
        try LocalVLMProviderFactory.provider(for: configuration)
    }
}

@Test func localVLMFactoryRejectsRemoteOpenAICompatibleEndpointByDefault() {
    let configuration = LocalVLMConfiguration(
        enabled: true,
        provider: .openAICompatible,
        modelID: "vision-model",
        endpointURLString: "https://gpu.example.com/v1"
    )

    #expect(throws: ToolExecutionError.self) {
        try LocalVLMProviderFactory.provider(for: configuration)
    }
}

@Test func localVLMFactoryAllowsRemoteOpenAICompatibleEndpointWithExplicitFlag() throws {
    let configuration = LocalVLMConfiguration(
        enabled: true,
        provider: .openAICompatible,
        modelID: "vision-model",
        endpointURLString: "https://gpu.example.com/v1",
        allowNonLocalEndpoint: true
    )

    let anyProvider = try #require(try LocalVLMProviderFactory.provider(for: configuration))
    let provider = try #require(anyProvider as? OpenAICompatibleVLMProvider)

    #expect(provider.providerName == "OpenAI-compatible")
    #expect(provider.modelID == "vision-model")
    #expect(provider.endpointURL.absoluteString == "https://gpu.example.com/v1")
}

@Test func localVLMProviderExecutorReturnsFakeProviderResponse() async throws {
    let imageURL = try TestImageFactory.writeImageData()
    defer {
        try? FileManager.default.removeItem(at: imageURL)
    }

    let response = try await LocalVLMProviderExecutor.answer(
        using: FakeLocalVLMProvider(),
        imageURL: imageURL,
        prompt: "describe",
        options: LocalVLMRequestOptions(maxTokens: 5, timeoutSeconds: 1)
    )

    #expect(response.text == "A visible test screen.")
    #expect(response.metadata["imageExists"] == "true")
    #expect(response.metadata["maxTokens"] == "5")
}

@Test func localVLMProviderExecutorRejectsInvalidImagePath() async {
    var caughtInvalidPath = false

    do {
        _ = try await LocalVLMProviderExecutor.answer(
            using: FakeLocalVLMProvider(),
            imageURL: URL(fileURLWithPath: "/tmp/cerberus-missing-vlm-image.png"),
            prompt: "describe",
            options: LocalVLMRequestOptions(maxTokens: 5, timeoutSeconds: 1)
        )
    } catch LocalVLMProviderError.invalidImagePath {
        caughtInvalidPath = true
    } catch {}

    #expect(caughtInvalidPath)
}

@Test func localVLMProviderExecutorTimesOutFakeProvider() async throws {
    let imageURL = try TestImageFactory.writeImageData()
    defer {
        try? FileManager.default.removeItem(at: imageURL)
    }
    var caughtTimeout = false

    do {
        _ = try await LocalVLMProviderExecutor.answer(
            using: DelayedLocalVLMProvider(delayNanoseconds: 2_000_000_000),
            imageURL: imageURL,
            prompt: "describe",
            options: LocalVLMRequestOptions(maxTokens: 5, timeoutSeconds: 1)
        )
    } catch LocalVLMProviderError.timedOut {
        caughtTimeout = true
    } catch {}

    #expect(caughtTimeout)
}

@Test func localVLMProviderExecutorReportsCancellation() async throws {
    let imageURL = try TestImageFactory.writeImageData()
    defer {
        try? FileManager.default.removeItem(at: imageURL)
    }
    let task = Task {
        try await LocalVLMProviderExecutor.answer(
            using: DelayedLocalVLMProvider(delayNanoseconds: 5_000_000_000),
            imageURL: imageURL,
            prompt: "describe",
            options: LocalVLMRequestOptions(maxTokens: 5, timeoutSeconds: 45)
        )
    }
    task.cancel()
    var caughtCancellation = false

    do {
        _ = try await task.value
    } catch LocalVLMProviderError.cancelled {
        caughtCancellation = true
    } catch is CancellationError {
        caughtCancellation = true
    } catch {}

    #expect(caughtCancellation)
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

@Test func urlSessionLocalVLMHTTPTransportRejectsNon200Response() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer {
        session.invalidateAndCancel()
    }
    MockURLProtocol.state.set(statusCode: 500, body: "failed")
    let transport = URLSessionLocalVLMHTTPTransport(session: session)

    await #expect(throws: ToolExecutionError.self) {
        try await transport.postJSON(
            body: Data("{}".utf8),
            to: try #require(URL(string: "http://localhost:11434/api/generate")),
            timeoutSeconds: 3
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
        arguments: ["answer", "{model}", "{maxTokens}", "{image}", "{prompt}"]
    )

    let response = try await provider.answer(
        imageURL: URL(fileURLWithPath: "/tmp/no-image.png"),
        prompt: "describe",
        options: LocalVLMRequestOptions(maxTokens: 7, timeoutSeconds: 2)
    )

    #expect(response.text == "answer sub-model 7 /tmp/no-image.png describe")
}

@Test func localVLMSubprocessProviderRequiresImageAndPromptTemplates() async {
    let provider = LocalVLMSubprocessProvider(
        providerName: "MLX-VLM",
        modelID: "sub-model",
        executableURL: URL(fileURLWithPath: "/bin/echo"),
        arguments: ["answer", "{model}"]
    )

    await #expect(throws: ToolExecutionError.self) {
        try await provider.answer(
            imageURL: URL(fileURLWithPath: "/tmp/no-image.png"),
            prompt: "describe",
            options: LocalVLMRequestOptions(maxTokens: 7, timeoutSeconds: 2)
        )
    }
}

@Test func localVLMSubprocessProviderReportsFailure() async {
    let provider = LocalVLMSubprocessProvider(
        providerName: "MLX-VLM",
        modelID: "sub-model",
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "echo failed >&2; exit 3", "{image}", "{prompt}"]
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
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "sleep 2", "{image}", "{prompt}"]
    )

    await #expect(throws: ToolExecutionError.self) {
        try await provider.answer(
            imageURL: URL(fileURLWithPath: "/tmp/no-image.png"),
            prompt: "describe",
            options: LocalVLMRequestOptions(maxTokens: 7, timeoutSeconds: 1)
        )
    }
}

@Test func localVLMSubprocessProviderReportsCancellation() async {
    let provider = LocalVLMSubprocessProvider(
        providerName: "MLX-VLM",
        modelID: "sub-model",
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "sleep 5", "{image}", "{prompt}"]
    )
    let task = Task {
        try await provider.answer(
            imageURL: URL(fileURLWithPath: "/tmp/no-image.png"),
            prompt: "describe",
            options: LocalVLMRequestOptions(maxTokens: 7, timeoutSeconds: 45)
        )
    }
    task.cancel()
    var caughtCancellation = false

    do {
        _ = try await task.value
    } catch LocalVLMProviderError.cancelled {
        caughtCancellation = true
    } catch is CancellationError {
        caughtCancellation = true
    } catch {}

    #expect(caughtCancellation)
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
    #expect(result.metadata["scope"] == "main_display")
    #expect(FileManager.default.fileExists(atPath: imagePath))
}

@Test func screenDescribeRunsConfiguredLocalVLMForActiveWindowScope() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerberus-vlm-active-window-test-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }
    let image = try #require(TestImageFactory.makeTestImage())
    let tool = ScreenDescribeTool(
        provider: FakeLocalVLMProvider(),
        options: LocalVLMRequestOptions(maxTokens: 24, timeoutSeconds: 2),
        outputDirectoryURL: directoryURL,
        cachePolicy: ScreenSnapshotCachePolicy(maximumFileCount: 2, maximumAge: 60),
        hasScreenCaptureAccess: { true },
        captureImage: { scope in
            CapturedScreenImage(image: image, scope: scope, sourceDescription: "test \(scope.rawValue)")
        }
    )

    let result = try await tool.run(arguments: ScreenDescribeTool.Arguments(
        prompt: "what is visible?",
        scope: "active_window"
    ))

    #expect(result.spokenSummary == "A visible test screen.")
    #expect(result.metadata["scope"] == "active_window")
    #expect(result.metadata["maxTokens"] == "24")
    #expect(result.untrustedPayload.contains("scope: active_window"))
}

@Test func screenDescribeWrapsGUIControlRequestsAsPassiveObservation() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerberus-vlm-passive-test-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }
    let image = try #require(TestImageFactory.makeTestImage())
    let recorder = PromptRecorder()
    let tool = ScreenDescribeTool(
        provider: RecordingPromptLocalVLMProvider(recorder: recorder),
        options: LocalVLMRequestOptions(maxTokens: 24, timeoutSeconds: 2),
        outputDirectoryURL: directoryURL,
        cachePolicy: ScreenSnapshotCachePolicy(maximumFileCount: 2, maximumAge: 60),
        hasScreenCaptureAccess: { true },
        captureImage: { scope in
            CapturedScreenImage(image: image, scope: scope, sourceDescription: "test \(scope.rawValue)")
        }
    )

    let result = try await tool.run(arguments: ScreenDescribeTool.Arguments(
        prompt: "click the button and operate this UI"
    ))
    let prompt = try #require(await recorder.lastPrompt())

    #expect(prompt.contains("Passive screen description only."))
    #expect(prompt.contains("Do not click, type, navigate, operate apps"))
    #expect(prompt.contains("If the user asks for GUI-agent behavior"))
    #expect(prompt.contains("click the button and operate this UI"))
    #expect(result.spokenSummary == "I can describe the UI, but I cannot operate it.")
    #expect(result.untrustedPayload.contains("question: click the button and operate this UI"))
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
    let legacyDiskLookupLabel = ["File", "search", "folders"].joined(separator: " ")
    let context = AssistantContext(
        activeApplicationName: "Xcode",
        allowedToolNames: DefaultToolCatalog.summaries.map(\.name),
        activeApplicationHints: ["Use screen reads only; never operate the app."]
    )

    #expect(context.promptFragment.contains("Active app: Xcode"))
    #expect(context.promptFragment.contains("Allowed tools: screen.barcodes, screen.ocr, screen.snapshot, screen.ui_elements"))
    #expect(!context.promptFragment.contains(legacyDiskLookupLabel))
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
        name("mcp", "list"),
        name("memory", "read"),
        name("memory", "delete"),
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
