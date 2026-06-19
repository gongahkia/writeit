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
    try await waitUntil { transcriber.cancelCount == 1 }

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

@MainActor
@Test func appModelSettingsPersistExpectedTogglesAcrossRelaunch() {
    let keys = CerberusSettingsKeys.persistedKeys
    let priorValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
    defer {
        for (key, value) in priorValues {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    for key in keys {
        UserDefaults.standard.removeObject(forKey: key)
    }

    let model = CerberusAppModel(
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )
    model.requiresConfirmationForAllTools = true
    model.requiresLocalFoundationModels = false
    model.usesConfiguredAdapter = false
    model.hotKeyConfigurationID = HotKeyConfiguration.commandOptionSpace.id
    model.prefersSoundWakeWordClassifier = true
    model.routesSpeechDirectlyToAirPods = true
    model.allowsMailBodySearch = true
    model.wakePhrase = "hello cerberus"
    model.isShellProposalMode = false
    model.headGestureCooldownSeconds = 0.8

    let relaunchedModel = CerberusAppModel(
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    #expect(relaunchedModel.requiresConfirmationForAllTools)
    #expect(!relaunchedModel.requiresLocalFoundationModels)
    #expect(!relaunchedModel.usesConfiguredAdapter)
    #expect(relaunchedModel.hotKeyConfigurationID == HotKeyConfiguration.commandOptionSpace.id)
    #expect(relaunchedModel.prefersSoundWakeWordClassifier)
    #expect(relaunchedModel.routesSpeechDirectlyToAirPods)
    #expect(relaunchedModel.allowsMailBodySearch)
    #expect(relaunchedModel.wakePhrase == "hello cerberus")
    #expect(!relaunchedModel.isShellProposalMode)
    #expect(relaunchedModel.headGestureCooldownSeconds == 0.8)
}

@MainActor
@Test func appModelSessionSettingsResetAcrossRelaunch() {
    let model = CerberusAppModel(
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )
    model.toolProfileID = ToolProfile.explicitOperator.id
    model.isAutoSilenceEnabled = false
    model.isVoiceConfirmationEnabled = false
    model.isSessionMemoryWriteDisabled = true
    model.isMCPToolEnabled = true
    model.isShellToolEnabled = true
    model.isHeadGestureValidationLoggingEnabled = true
    model.headNodThreshold = 0.9
    model.headShakeThreshold = 0.9

    let relaunchedModel = CerberusAppModel(
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    #expect(relaunchedModel.toolProfileID == ToolProfile.trustedDesk.id)
    #expect(relaunchedModel.isAutoSilenceEnabled)
    #expect(relaunchedModel.isVoiceConfirmationEnabled)
    #expect(!relaunchedModel.isSessionMemoryWriteDisabled)
    #expect(!relaunchedModel.isMCPToolEnabled)
    #expect(!relaunchedModel.isShellToolEnabled)
    #expect(!relaunchedModel.isHeadGestureValidationLoggingEnabled)
    #expect(relaunchedModel.headNodThreshold == 0.35)
    #expect(relaunchedModel.headShakeThreshold == 0.45)
}

@MainActor
@Test func appModelSpeaksLatestAuditAction() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("audit.log")
    let auditLog = AuditLog(fileURL: fileURL, fixedSigningKeyData: Data(repeating: 7, count: 32))
    _ = try await auditLog.append(toolName: "calendar.read", argumentsSummary: "today", resultSummary: "3 events")
    _ = try await auditLog.append(toolName: "mail.search", argumentsSummary: "invoice", resultSummary: "2 messages")
    let speaker = FakeSpeaker()
    let model = CerberusAppModel(
        speaker: speaker,
        auditLog: auditLog,
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    model.answerLastToolAction()
    try await waitUntil {
        speaker.spoken == ["Last tool call: mail.search. Result: 2 messages"]
    }

    #expect(model.statusLine == "Last tool call: mail.search. Result: 2 messages")
    #expect(model.recentAuditEntries.first?.toolName == "mail.search")
}

@MainActor
@Test func appModelRefreshesTranscriptHistoryFromStore() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("transcripts.jsonl.enc")
    let store = EncryptedTranscriptStore(fileURL: fileURL, fixedKeyData: Data(repeating: 11, count: 32))
    try await store.append(TranscriptRecord(
        timestamp: Date(timeIntervalSince1970: 1),
        request: "older",
        response: "Older response."
    ))
    try await store.append(TranscriptRecord(
        timestamp: Date(timeIntervalSince1970: 2),
        request: "newer",
        response: "Newer response."
    ))
    let model = CerberusAppModel(
        transcriptStore: store,
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    model.refreshTranscriptRecords()
    try await waitUntil {
        model.transcriptRecords.map(\.request) == ["newer", "older"]
    }

    #expect(model.transcriptRecords.first?.response == "Newer response.")
}

@MainActor
@Test func appModelRefreshesAuditPanelEntriesFromStore() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("audit.log")
    let auditLog = AuditLog(fileURL: fileURL, fixedSigningKeyData: Data(repeating: 13, count: 32))
    _ = try await auditLog.append(toolName: "calendar.read", argumentsSummary: "today", resultSummary: "3 events")
    _ = try await auditLog.append(toolName: "files.search", argumentsSummary: "notes", resultSummary: "2 files")
    let model = CerberusAppModel(
        auditLog: auditLog,
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    model.refreshAuditEntries()
    try await waitUntil {
        model.recentAuditEntries.map(\.toolName) == ["files.search", "calendar.read"]
    }

    #expect(model.recentAuditEntries.first?.resultSummary == "2 files")
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 3_000_000_000,
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
