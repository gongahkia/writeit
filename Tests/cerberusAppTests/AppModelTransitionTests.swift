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
    var sampleResult = "sample"
    private(set) var plannedRequests: [String] = []

    init(planResult: AssistantPlan) {
        self.planResult = planResult
    }

    func setSampleResult(_ sampleResult: String) {
        self.sampleResult = sampleResult
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
        sampleResult
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
private final class FakePermissionCenter: PermissionChecking {
    var snapshots: [PermissionSnapshot]

    init(snapshots: [PermissionSnapshot]) {
        self.snapshots = snapshots
    }

    func currentSnapshots() -> [PermissionSnapshot] {
        snapshots
    }

    func request(_ kind: SystemPermission) async -> PermissionSnapshot {
        snapshots.first { $0.kind == kind } ?? PermissionSnapshot(kind: kind, state: .unknown)
    }
}

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
@Test func appModelMenuBarTintIsRedWhileListening() async throws {
    let transcriber = FakeTranscriber()
    let model = CerberusAppModel(
        transcriber: transcriber,
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    model.startListening()
    try await waitUntil { transcriber.isRunning }

    #expect(model.state == .listening)
    #expect(model.menuBarStatusTint == .red)
}

@MainActor
@Test func appModelMenuBarTintReturnsPrimaryAfterListeningStops() async throws {
    let transcriber = FakeTranscriber()
    let model = CerberusAppModel(
        transcriber: transcriber,
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    model.startListening()
    try await waitUntil { transcriber.isRunning }
    model.cancel()
    try await waitUntil { transcriber.cancelCount == 1 }

    #expect(model.state == .idle)
    #expect(model.menuBarStatusTint == .primary)
}

@MainActor
@Test func appModelMenuBarTintIsRedDuringWakePhraseMonitoring() {
    let tint = MenuBarStatusTint.resolve(
        state: .idle,
        isConfirmationVoiceActive: false,
        isWakeWordMonitoring: true
    )

    #expect(tint == .red)
}

@MainActor
@Test func appModelMenuBarTintIsRedDuringConfirmationVoiceCapture() {
    let tint = MenuBarStatusTint.resolve(
        state: .awaitingConfirm,
        isConfirmationVoiceActive: true,
        isWakeWordMonitoring: false
    )

    #expect(tint == .red)
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
@Test func appModelSetupAccessActionOpensPermissionsPanelWhenPermissionIsMissing() {
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

    let permissions = FakePermissionCenter(snapshots: [
        PermissionSnapshot(kind: .microphone, state: .notDetermined)
    ])
    let model = CerberusAppModel(
        permissionCenter: permissions,
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    model.selectedPanelSection = .session
    model.openSetupAccessPanelIfNeeded()

    #expect(model.shouldShowOnboarding)
    #expect(model.selectedPanelSection == .permissions)
}

@MainActor
@Test func appModelMCPElicitationDraftsCoverPrimitiveControlTypes() throws {
    let fields = [
        MCPElicitationField(
            name: "enabled",
            type: .boolean,
            title: "Enabled",
            description: nil,
            required: true,
            defaultValue: "true",
            enumValues: [],
            enumNames: []
        ),
        MCPElicitationField(
            name: "team",
            type: .string,
            title: "Team",
            description: nil,
            required: true,
            defaultValue: nil,
            enumValues: ["eng", "design"],
            enumNames: ["Engineering", "Design"]
        ),
        MCPElicitationField(
            name: "ratio",
            type: .number,
            title: "Ratio",
            description: nil,
            required: true,
            defaultValue: "0.5",
            enumValues: [],
            enumNames: []
        ),
        MCPElicitationField(
            name: "count",
            type: .integer,
            title: "Count",
            description: nil,
            required: true,
            defaultValue: "2",
            enumValues: [],
            enumNames: []
        ),
        MCPElicitationField(
            name: "note",
            type: .string,
            title: "Note",
            description: nil,
            required: true,
            defaultValue: "ship it",
            enumValues: [],
            enumNames: []
        )
    ]

    let drafts = CerberusAppModel.defaultElicitationFieldDrafts(for: fields)
    let valuesByName = Dictionary(uniqueKeysWithValues: drafts.map { ($0.field.name, $0.value) })
    let contentJSON = try CerberusAppModel.elicitationContentJSON(from: drafts)

    #expect(valuesByName == [
        "enabled": "true",
        "team": "eng",
        "ratio": "0.5",
        "count": "2",
        "note": "ship it"
    ])
    #expect(contentJSON.contains(#""enabled" : true"#))
    #expect(contentJSON.contains(#""team" : "eng""#))
    #expect(contentJSON.contains(#""ratio" : 0.5"#))
    #expect(contentJSON.contains(#""count" : 2"#))
    #expect(contentJSON.contains(#""note" : "ship it""#))
}

@MainActor
@Test func appModelToolAllowlistIncludesAllAmbientToolsByDefault() {
    let model = CerberusAppModel(
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )
    let toolNames = model.availableAmbientToolSummaries.map(\.name)
    let displayText = model.enabledToolDisplayText

    #expect(!toolNames.isEmpty)
    #expect(Set(toolNames).count == toolNames.count)
    #expect(toolNames.allSatisfy { model.isAmbientToolEnabled($0) })
    #expect(toolNames.allSatisfy { displayText.contains($0) })
    #expect(model.disabledAmbientToolCount == 0)
}

@MainActor
@Test func appModelToolAllowlistOmitsSeveralDisabledTools() {
    let model = CerberusAppModel(
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )
    let disabledToolNames = Array(model.availableAmbientToolSummaries.map(\.name).prefix(3))

    for toolName in disabledToolNames {
        model.setAmbientTool(toolName, enabled: false)
    }

    let displayText = model.enabledToolDisplayText

    #expect(disabledToolNames.count == 3)
    #expect(model.disabledAmbientToolCount == disabledToolNames.count)
    #expect(disabledToolNames.allSatisfy { !model.isAmbientToolEnabled($0) })
    #expect(disabledToolNames.allSatisfy { !displayText.contains($0) })
}

@MainActor
@Test func appModelMCPReviewHandlesLongPromptAndResponseDrafts() async throws {
    let longPrompt = String(repeating: "long prompt text ", count: 120)
    let longSystemPrompt = String(repeating: "system detail ", count: 80)
    let longResponse = String(repeating: "long response text ", count: 140)
    let assistant = FakeAssistant(planResult: AssistantPlan(
        intent: .answerDirectly,
        spokenResponse: "unused",
        requiresConfirmation: false
    ))
    await assistant.setSampleResult(longResponse)
    let model = CerberusAppModel(
        assistant: assistant,
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )
    let request = MCPSamplingRequest(
        serverName: "long-review",
        messagesText: longPrompt,
        systemPrompt: longSystemPrompt,
        maxTokens: 256,
        rawParamsJSON: "{}"
    )

    let responseTask = Task {
        try await model.handleMCPSamplingRequest(request)
    }
    try await waitUntil {
        model.pendingMCPClientRequest?.kind == .samplingPrompt
    }

    #expect(model.pendingMCPClientRequest?.summary.contains("long-review") == true)
    #expect(model.pendingMCPClientRequest?.detail == longSystemPrompt)
    #expect(model.mcpClientDraft == longPrompt)

    model.approveMCPClientRequest()
    try await waitUntil {
        model.pendingMCPClientRequest?.kind == .samplingResponse
    }

    #expect(model.pendingMCPClientRequest?.summary.contains("long-review") == true)
    #expect(model.mcpClientDraft == longResponse)

    model.approveMCPClientRequest()
    let response = try await responseTask.value

    #expect(response.text == longResponse)
    #expect(model.pendingMCPClientRequest == nil)
    #expect(model.mcpClientDraft.isEmpty)
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

@MainActor
@Test func appModelFileSearchFolderAddRemoveFlowUpdatesVisiblePaths() throws {
    let defaultsName = "cerberus-file-search-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer {
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
    }
    let store = FileSearchScopeStore(defaults: defaults)
    let directoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cerberus-file-search-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }
    let model = CerberusAppModel(
        fileSearchScopeStore: store,
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    model.addFileSearchScopePaths([directoryURL.path, directoryURL.path])

    #expect(model.fileSearchScopePaths == [directoryURL.path])
    #expect(model.statusLine == "File search folders updated.")

    model.removeFileSearchScope(directoryURL.path)

    #expect(model.fileSearchScopePaths.isEmpty)
    #expect(model.statusLine == "No file search folders approved.")
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 10_000_000_000,
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
