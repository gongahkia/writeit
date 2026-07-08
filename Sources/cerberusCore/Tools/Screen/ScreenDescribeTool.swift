import CoreGraphics
import Foundation
import FoundationModels

public struct ScreenDescribeTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let prompt: String
        public let scope: String?

        public init(prompt: String, scope: String? = nil) {
            self.prompt = prompt
            self.scope = scope
        }
    }

    public let name = "screen.describe"
    public let capability = "Answer a question about the visible screen image using a configured local VLM provider."
    public let mutatesState = false
    public let argumentSchema = #"{"prompt":"question about visible screen","scope":"main_display|active_window"}"#

    private let provider: any LocalVLMProviding
    private let options: LocalVLMRequestOptions
    private let outputDirectoryURL: URL
    private let cachePolicy: ScreenSnapshotCachePolicy
    private let hasScreenCaptureAccess: @Sendable () -> Bool
    private let captureImage: @Sendable (ScreenCaptureScope) async throws -> CapturedScreenImage

    public init(
        provider: any LocalVLMProviding,
        options: LocalVLMRequestOptions = LocalVLMRequestOptions(),
        outputDirectoryURL: URL = ScreenSnapshotTool.defaultOutputDirectoryURL(),
        cachePolicy: ScreenSnapshotCachePolicy = .default,
        hasScreenCaptureAccess: @escaping @Sendable () -> Bool = CGPreflightScreenCaptureAccess
    ) {
        self.init(
            provider: provider,
            options: options,
            outputDirectoryURL: outputDirectoryURL,
            cachePolicy: cachePolicy,
            hasScreenCaptureAccess: hasScreenCaptureAccess,
            captureImage: ScreenCaptureSupport.captureImage
        )
    }

    init(
        provider: any LocalVLMProviding,
        options: LocalVLMRequestOptions,
        outputDirectoryURL: URL,
        cachePolicy: ScreenSnapshotCachePolicy,
        hasScreenCaptureAccess: @escaping @Sendable () -> Bool,
        captureImage: @escaping @Sendable (ScreenCaptureScope) async throws -> CapturedScreenImage
    ) {
        self.provider = provider
        self.options = options
        self.outputDirectoryURL = outputDirectoryURL
        self.cachePolicy = cachePolicy
        self.hasScreenCaptureAccess = hasScreenCaptureAccess
        self.captureImage = captureImage
    }

    public func validate(_ arguments: Arguments) throws {
        let prompt = arguments.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw ToolExecutionError.invalidArguments("screen.describe requires a non-empty prompt.")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        guard hasScreenCaptureAccess() else {
            throw ToolExecutionError.denied("Screen Recording access is not granted.")
        }

        let prompt = arguments.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedScope = try ScreenCaptureScope.parse(arguments.scope)
        let capture = try await captureImage(requestedScope)
        let fileURL = outputDirectoryURL
            .appendingPathComponent(Self.fileName(for: Date()), isDirectory: false)
        try ScreenCaptureSupport.writePNG(capture.image, to: fileURL)
        try ScreenSnapshotCache.cleanDirectory(outputDirectoryURL, preserving: fileURL, policy: cachePolicy)

        let response = try await LocalVLMProviderExecutor.answer(
            using: provider,
            imageURL: fileURL,
            prompt: Self.passivePrompt(for: prompt),
            options: options
        )
        let answer = ScreenTextRedactor.redact(response.text)
        let imageSize = CGSize(width: capture.image.width, height: capture.image.height)

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: answer,
            untrustedPayload: Self.payload(
                answer: answer,
                prompt: prompt,
                imageSize: imageSize,
                scope: capture.scope,
                sourceDescription: capture.sourceDescription,
                providerName: provider.providerName,
                modelID: provider.modelID
            ),
            metadata: [
                "imagePath": fileURL.path,
                "imageWidth": "\(capture.image.width)",
                "imageHeight": "\(capture.image.height)",
                "scope": capture.scope.rawValue,
                "provider": provider.providerName,
                "modelID": provider.modelID
            ].merging(response.metadata) { current, _ in current }
        )
    }

    static func passivePrompt(for prompt: String) -> String {
        """
        Passive screen description only.
        Observe the supplied screenshot and answer the user's visual question.
        Do not click, type, navigate, operate apps, invoke tools, plan GUI actions, or provide step-by-step computer-control instructions.
        If the user asks for GUI-agent behavior, refuse that action briefly and provide only an observe-only description of relevant visible UI.

        User question:
        \(prompt)
        """
    }

    static func payload(
        answer: String,
        prompt: String,
        imageSize: CGSize,
        scope: ScreenCaptureScope,
        sourceDescription: String,
        providerName: String,
        modelID: String
    ) -> String {
        """
        scope: \(scope.rawValue)
        source: \(sourceDescription)
        image: \(Int(imageSize.width))x\(Int(imageSize.height))
        provider: \(providerName)
        model: \(modelID)
        question: \(ScreenTextRedactor.redact(prompt))
        answer: \(answer)
        """
    }

    private static func fileName(for date: Date) -> String {
        "screen-vlm-\(Int(date.timeIntervalSince1970))-\(UUID().uuidString).png"
    }
}
