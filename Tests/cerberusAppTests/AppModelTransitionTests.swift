import Foundation
import FoundationModels
import Testing
@testable import cerberusApp
import cerberusCore

@MainActor
private final class FakeTranscriber: AppTranscribing {
    private var onUpdate: (@MainActor @Sendable (TranscriptionUpdate) -> Void)?
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    private(set) var isRunning = false

    func start(
        locale requestedLocale: Locale,
        onUpdate: @escaping @MainActor @Sendable (TranscriptionUpdate) -> Void
    ) async throws {
        isRunning = true
        self.onUpdate = onUpdate
    }

    func stop() async {
        stopCount += 1
        isRunning = false
    }

    func cancel() async {
        cancelCount += 1
        isRunning = false
    }

    func emit(_ text: String, isFinal: Bool = false) {
        onUpdate?(TranscriptionUpdate(text: text, isFinal: isFinal))
    }
}

@MainActor
private final class FakeSpeaker: AppSpeaking {
    private(set) var spoken: [String] = []
    private(set) var stopCount = 0
    var completesImmediately = false

    func setPreferredOutputDevice(_ device: AudioOutputDevice?) {}

    func speak(
        _ text: String,
        rate: Float,
        completion: (@MainActor @Sendable () -> Void)?
    ) {
        spoken.append(text)
        if completesImmediately {
            completion?()
        }
    }

    func stop() {
        stopCount += 1
    }
}

private actor FakeAssistant: AppAssistanting {
    var planResult: AssistantPlan
    private(set) var plannedRequests: [String] = []

    init(planResult: AssistantPlan) {
        self.planResult = planResult
    }

    func updateToolConfiguration(
        toolSummaries: [ToolSummary],
        readOnlyNativeTools: [any FoundationModels.Tool]
    ) async {}

    func updateModel(_ model: SystemLanguageModel) async {}

    func plan(for request: String, context: AssistantContext) async throws -> AssistantPlan {
        plannedRequests.append(request)
        return planResult
    }

    func answerWithReadOnlyTools(for request: String, context: AssistantContext) async throws -> String {
        "native answer"
    }

    func sampleForMCP(messagesText: String, systemPrompt: String?) async throws -> String {
        "sample"
    }

    func summarize(toolResult: ToolResult, for request: String) async throws -> String {
        toolResult.spokenSummary
    }
}

private struct StubTool: AssistantTool {
    struct Arguments: Codable, Sendable {}

    let name: String
    let capability = "Return a stub result."
    let mutatesState: Bool

    func run(arguments: Arguments) async throws -> ToolResult {
        ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Tool done.",
            untrustedPayload: ""
        )
    }
}

private struct WaitTimeout: Error {}

@MainActor
@Test func appModelTransitionsFromListeningToDirectAnswer() async throws {
    let transcriber = FakeTranscriber()
    let speaker = FakeSpeaker()
    let assistant = FakeAssistant(planResult: AssistantPlan(
        intent: .answerDirectly,
        spokenResponse: "It is handled.",
        requiresConfirmation: false
    ))
    let model = CerberusAppModel(
        transcriber: transcriber,
        speaker: speaker,
        assistant: assistant,
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    model.startListening()
    try await waitUntil { transcriber.isRunning }
    transcriber.emit("hello")
    model.finishListeningAndProcess()
    try await waitUntil { model.state == .speaking }

    #expect(model.recentEvents.contains("idle -> listening"))
    #expect(model.recentEvents.contains("listening -> reasoning"))
    #expect(model.recentEvents.first == "reasoning -> speaking")
    #expect(model.transcriptDraft == "hello")
    #expect(speaker.spoken == ["It is handled."])
    #expect(await assistant.plannedRequests == ["hello"])
}

@MainActor
@Test func appModelRequiresConfirmationThenExecutesMutatingTool() async throws {
    let speaker = FakeSpeaker()
    let assistant = FakeAssistant(planResult: AssistantPlan(
        intent: .callTool,
        spokenResponse: "I need confirmation.",
        requiresConfirmation: true,
        toolName: "app.control",
        toolArgumentsJSON: "{}",
        toolArgumentsSummary: "Run stub"
    ))
    let registry = try ToolRegistry(tools: [AnyAssistantTool(StubTool(name: "app.control", mutatesState: true))])
    let model = CerberusAppModel(
        speaker: speaker,
        assistant: assistant,
        toolRegistry: registry,
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    model.startListening()
    await Task.yield()
    model.transcriptDraft = "run stub"
    model.finishListeningAndProcess()
    try await waitUntil { model.state == .awaitingConfirm }

    #expect(model.pendingConfirmation?.summary == "Run stub")
    #expect(speaker.spoken == ["I need confirmation."])

    model.approvePendingConfirmation()
    try await waitUntil { model.state == .speaking }

    #expect(model.pendingConfirmation == nil)
    #expect(model.recentEvents.contains("awaiting_confirm -> executing"))
    #expect(model.recentEvents.first == "executing -> speaking")
    #expect(speaker.spoken.contains("Tool done."))
}

@MainActor
@Test func appModelCancelStopsSpeechAndReturnsIdle() async throws {
    let transcriber = FakeTranscriber()
    let speaker = FakeSpeaker()
    let model = CerberusAppModel(
        transcriber: transcriber,
        speaker: speaker,
        startsRuntimeServices: false
    )

    model.startListening()
    await Task.yield()
    model.cancel()
    try await waitUntil { model.state == .idle }

    #expect(transcriber.cancelCount == 1)
    #expect(speaker.stopCount == 1)
    #expect(model.transcriptDraft.isEmpty)
    #expect(model.recentEvents.first == "listening -> idle")
}

@MainActor
@Test func appModelSetupSkipPersistsAcrossRelaunch() {
    let key = CerberusSettingsKeys.onboardingSkipped
    let prior = UserDefaults.standard.object(forKey: key)
    defer {
        if let prior {
            UserDefaults.standard.set(prior, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    UserDefaults.standard.removeObject(forKey: key)
    let model = CerberusAppModel(
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )
    model.skipOnboarding()

    let relaunchedModel = CerberusAppModel(
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    #expect(relaunchedModel.hasSkippedOnboarding)
    #expect(UserDefaults.standard.bool(forKey: key))
}

@MainActor
@Test func appModelSetupResetClearsSkipFlag() {
    let key = CerberusSettingsKeys.onboardingSkipped
    let prior = UserDefaults.standard.object(forKey: key)
    defer {
        if let prior {
            UserDefaults.standard.set(prior, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    UserDefaults.standard.set(true, forKey: key)
    let model = CerberusAppModel(
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )
    model.resetOnboarding()

    #expect(!model.hasSkippedOnboarding)
    #expect(!UserDefaults.standard.bool(forKey: key))
    #expect(!model.permissionSnapshots.isEmpty)
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    predicate: @MainActor @escaping () -> Bool
) async throws {
    let start = ContinuousClock.now
    while await !predicate() {
        if start.duration(to: .now) > .nanoseconds(Int64(timeoutNanoseconds)) {
            throw WaitTimeout()
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}
