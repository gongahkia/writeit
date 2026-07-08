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
    var requestResults: [SystemPermission: PermissionSnapshot]

    init(snapshots: [PermissionSnapshot], requestResults: [SystemPermission: PermissionSnapshot] = [:]) {
        self.snapshots = snapshots
        self.requestResults = requestResults
    }

    func currentSnapshots() -> [PermissionSnapshot] {
        snapshots
    }

    func request(_ kind: SystemPermission) async -> PermissionSnapshot {
        let snapshot = requestResults[kind] ?? snapshots.first { $0.kind == kind } ?? PermissionSnapshot(kind: kind, state: .unknown)
        if let index = snapshots.firstIndex(where: { $0.kind == kind }) {
            snapshots[index] = snapshot
        } else {
            snapshots.append(snapshot)
        }
        return snapshot
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

    model.cancel()
}

@MainActor
@Test func appModelRequiresConfirmationThenExecutesConfirmedScreenRead() async throws {
    let transcriber = FakeTranscriber()
    let speaker = FakeSpeaker()
    let assistant = FakeAssistant(planResult: AssistantPlan(
        intent: .callTool,
        spokenResponse: "I need confirmation.",
        requiresConfirmation: true,
        toolName: "screen.ocr",
        toolArgumentsJSON: "{}",
        toolArgumentsSummary: "Read screen"
    ))
    let registry = try ToolRegistry(tools: [AnyAssistantTool(StubTool(name: "screen.ocr", mutatesState: false))])
    let model = CerberusAppModel(
        transcriber: transcriber,
        speaker: speaker,
        assistant: assistant,
        toolRegistry: registry,
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    model.startListening()
    await Task.yield()
    model.transcriptDraft = "read screen"
    model.finishListeningAndProcess()
    try await waitUntil { model.state == .awaitingConfirm }

    #expect(model.pendingConfirmation?.summary == "Read screen")
    #expect(speaker.spoken == ["I need confirmation."])

    model.approvePendingConfirmation()
    try await waitUntil { model.state == .speaking }

    #expect(model.pendingConfirmation == nil)
    #expect(model.recentEvents.contains("awaiting_confirm -> executing"))
    #expect(model.recentEvents.first == "executing -> speaking")
    #expect(speaker.spoken.contains("Tool done."))

    model.cancel()
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
    let keys = [CerberusSettingsKeys.onboardingSkipped, CerberusSettingsKeys.onboardingCurrentPermission]
    let prior = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
    defer {
        for (key, value) in prior {
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
    UserDefaults.standard.set(SystemPermission.microphone.rawValue, forKey: CerberusSettingsKeys.onboardingCurrentPermission)
    model.skipOnboarding()

    let relaunchedModel = CerberusAppModel(
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    #expect(relaunchedModel.hasSkippedOnboarding)
    #expect(UserDefaults.standard.bool(forKey: CerberusSettingsKeys.onboardingSkipped))
    #expect(UserDefaults.standard.string(forKey: CerberusSettingsKeys.onboardingCurrentPermission) == nil)
}

@MainActor
@Test func appModelSetupResetClearsSkipFlag() {
    let keys = [CerberusSettingsKeys.onboardingSkipped, CerberusSettingsKeys.onboardingCurrentPermission]
    let prior = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
    defer {
        for (key, value) in prior {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    UserDefaults.standard.set(true, forKey: CerberusSettingsKeys.onboardingSkipped)
    UserDefaults.standard.set(SystemPermission.accessibility.rawValue, forKey: CerberusSettingsKeys.onboardingCurrentPermission)
    let model = CerberusAppModel(
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )
    model.resetOnboarding()

    #expect(!model.hasSkippedOnboarding)
    #expect(!UserDefaults.standard.bool(forKey: CerberusSettingsKeys.onboardingSkipped))
    #expect(UserDefaults.standard.string(forKey: CerberusSettingsKeys.onboardingCurrentPermission) == nil)
    #expect(!model.permissionSnapshots.isEmpty)
}

@MainActor
@Test func appModelOnboardingResumesPersistedPermissionAcrossRelaunch() {
    let keys = [CerberusSettingsKeys.onboardingSkipped, CerberusSettingsKeys.onboardingCurrentPermission]
    let prior = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
    defer {
        for (key, value) in prior {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    UserDefaults.standard.removeObject(forKey: CerberusSettingsKeys.onboardingSkipped)
    UserDefaults.standard.set(SystemPermission.accessibility.rawValue, forKey: CerberusSettingsKeys.onboardingCurrentPermission)
    let permissions = FakePermissionCenter(snapshots: [
        PermissionSnapshot(kind: .microphone, state: .notDetermined),
        PermissionSnapshot(kind: .accessibility, state: .denied),
        PermissionSnapshot(kind: .screenRecording, state: .notDetermined)
    ])
    let model = CerberusAppModel(
        permissionCenter: permissions,
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    #expect(model.nextPermissionSnapshot?.kind == .accessibility)
}

@MainActor
@Test func appModelOnboardingPersistsAndAdvancesRequestedPermission() async throws {
    let keys = [CerberusSettingsKeys.onboardingSkipped, CerberusSettingsKeys.onboardingCurrentPermission]
    let prior = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
    defer {
        for (key, value) in prior {
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
    let permissions = FakePermissionCenter(
        snapshots: [
            PermissionSnapshot(kind: .microphone, state: .notDetermined),
            PermissionSnapshot(kind: .speechRecognition, state: .notDetermined)
        ],
        requestResults: [
            .microphone: PermissionSnapshot(kind: .microphone, state: .granted)
        ]
    )
    let model = CerberusAppModel(
        permissionCenter: permissions,
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    model.requestPermission(.microphone)
    try await waitUntil {
        model.onboardingCurrentPermissionID == SystemPermission.speechRecognition.rawValue
    }

    #expect(model.permissionSnapshots.first { $0.kind == .microphone }?.state == .granted)
    #expect(model.nextPermissionSnapshot?.kind == .speechRecognition)
    #expect(UserDefaults.standard.string(forKey: CerberusSettingsKeys.onboardingCurrentPermission) == SystemPermission.speechRecognition.rawValue)
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
    model.wakePhrase = "hello cerberus"
    model.headNodThreshold = 0.55
    model.headShakeThreshold = 0.65
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
    #expect(relaunchedModel.wakePhrase == "hello cerberus")
    #expect(relaunchedModel.headNodThreshold == 0.55)
    #expect(relaunchedModel.headShakeThreshold == 0.65)
    #expect(relaunchedModel.headGestureCooldownSeconds == 0.8)
}

@MainActor
@Test func appModelSessionSettingsResetAcrossRelaunch() {
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
    UserDefaults.standard.removeObject(forKey: CerberusSettingsKeys.headNodThreshold)
    UserDefaults.standard.removeObject(forKey: CerberusSettingsKeys.headShakeThreshold)

    let model = CerberusAppModel(
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )
    model.toolProfileID = ToolProfile.visionOnly.id
    model.isAutoSilenceEnabled = false
    model.isVoiceConfirmationEnabled = false
    model.isHeadGestureValidationLoggingEnabled = true
    model.headNodThreshold = 0.9
    model.headShakeThreshold = 0.9

    let relaunchedModel = CerberusAppModel(
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )

    #expect(relaunchedModel.toolProfileID == ToolProfile.visionOnly.id)
    #expect(relaunchedModel.isAutoSilenceEnabled)
    #expect(relaunchedModel.isVoiceConfirmationEnabled)
    #expect(!relaunchedModel.isHeadGestureValidationLoggingEnabled)
    #expect(relaunchedModel.headNodThreshold == 0.8)
    #expect(relaunchedModel.headShakeThreshold == 0.8)
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
    timeoutNanoseconds: UInt64 = 30_000_000_000,
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
