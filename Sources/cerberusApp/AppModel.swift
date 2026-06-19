import AppKit
import AVFoundation
import Foundation
import FoundationModels
import UniformTypeIdentifiers
import cerberusCore

struct PendingMCPClientRequest: Identifiable {
    enum Kind {
        case samplingPrompt
        case samplingResponse
        case elicitation
    }

    let id = UUID()
    let kind: Kind
    let serverName: String
    let summary: String
    let detail: String

    var title: String {
        switch kind {
        case .samplingPrompt:
            "MCP sampling request"
        case .samplingResponse:
            "MCP sampling response"
        case .elicitation:
            "MCP elicitation request"
        }
    }

    var draftLabel: String {
        switch kind {
        case .samplingPrompt:
            "Prompt"
        case .samplingResponse:
            "Response"
        case .elicitation:
            "Content JSON"
        }
    }

    var approveTitle: String {
        switch kind {
        case .samplingPrompt:
            "Send"
        case .samplingResponse:
            "Return"
        case .elicitation:
            "Accept"
        }
    }

    var allowsDecline: Bool {
        kind == .elicitation
    }
}

private let defaultHeadGestureCooldownSeconds = 1.2

struct MCPClientElicitationFieldDraft: Identifiable {
    let field: MCPElicitationField
    var value: String

    var id: String {
        field.id
    }
}

struct AppDataLocation: Identifiable, Equatable {
    let name: String
    let url: URL

    var id: String {
        name
    }
}

private enum MCPClientRequestDecision: Sendable {
    case approve(String)
    case decline
    case cancel
}

@MainActor
protocol AppTranscribing: AnyObject {
    var isRunning: Bool { get }

    func start(
        locale requestedLocale: Locale,
        onUpdate: @escaping @MainActor @Sendable (TranscriptionUpdate) -> Void
    ) async throws
    func stop() async
    func cancel() async
}

@MainActor
protocol AppSpeaking: AnyObject {
    func setPreferredOutputDevice(_ device: AudioOutputDevice?)
    func speak(
        _ text: String,
        rate: Float,
        completion: (@MainActor @Sendable () -> Void)?
    )
    func stop()
}

protocol AppAssistanting: Sendable {
    func updateToolConfiguration(
        toolSummaries: [ToolSummary],
        readOnlyNativeTools: [any FoundationModels.Tool]
    ) async
    func updateModel(_ model: SystemLanguageModel) async
    func plan(for request: String, context: AssistantContext) async throws -> AssistantPlan
    func answerWithReadOnlyTools(for request: String, context: AssistantContext) async throws -> String
    func sampleForMCP(messagesText: String, systemPrompt: String?) async throws -> String
    func summarize(toolResult: ToolResult, for request: String) async throws -> String
}

extension AppTranscribing {
    func start(
        onUpdate: @escaping @MainActor @Sendable (TranscriptionUpdate) -> Void
    ) async throws {
        try await start(locale: .current, onUpdate: onUpdate)
    }
}

extension AppSpeaking {
    func speak(
        _ text: String,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        speak(text, rate: AVSpeechUtteranceDefaultSpeechRate, completion: completion)
    }
}

extension Transcriber: AppTranscribing {}

extension Speaker: AppSpeaking {}

extension Assistant: AppAssistanting {}

final class MCPClientRequestBroker: @unchecked Sendable {
    @MainActor weak var model: CerberusAppModel?

    var handlers: MCPClientRequestHandlers {
        MCPClientRequestHandlers(
            sampling: { [weak self] request in
                guard let self else {
                    throw ToolExecutionError.denied("MCP sampling broker is unavailable.")
                }
                guard let model = await MainActor.run(body: { self.model }) else {
                    throw ToolExecutionError.denied("MCP sampling UI is unavailable.")
                }
                return try await model.handleMCPSamplingRequest(request)
            },
            elicitation: { [weak self] request in
                guard let self else {
                    throw ToolExecutionError.denied("MCP elicitation broker is unavailable.")
                }
                guard let model = await MainActor.run(body: { self.model }) else {
                    throw ToolExecutionError.denied("MCP elicitation UI is unavailable.")
                }
                return try await model.handleMCPElicitationRequest(request)
            }
        )
    }
}

@MainActor
final class CerberusAppModel: ObservableObject {
    @Published private(set) var stateMachine = AssistantStateMachine()
    @Published private(set) var statusLine = "Ready"
    @Published private(set) var recentEvents: [String] = []
    @Published private(set) var permissionSnapshots: [PermissionSnapshot] = []
    @Published private(set) var hasSkippedOnboarding = UserDefaults.standard.bool(forKey: CerberusSettingsKeys.onboardingSkipped)
    @Published private(set) var pendingConfirmation: PendingConfirmation?
    @Published private(set) var isConfirmationVoiceActive = false
    @Published private(set) var isWakeWordMonitoring = false
    @Published private(set) var wakeWordMonitorLine = WakeWordMonitorStatusLine.speechTranscription
    @Published private(set) var audioOutputRouteLine = "Output route unknown"
    @Published private(set) var speechOutputRoutingLine = "Speech follows system output"
    @Published private(set) var isAudioOutputLikelyAirPods = false
    @Published private(set) var recentAuditEntries: [AuditLogEntry] = []
    @Published private(set) var transcriptRecords: [TranscriptRecord] = []
    @Published private(set) var memoryRecords: [MemoryRecord] = []
    @Published private(set) var pendingMCPClientRequest: PendingMCPClientRequest?
    @Published private(set) var mcpListenerStatusLine = "MCP listener off"
    @Published private(set) var mcpServerHealthLines: [MCPServerHealthLine] = []
    @Published private(set) var foundationModelAvailabilityLine = "Foundation Models status unknown"
    @Published private(set) var foundationModelAvailabilityDetailLine = "Refresh to check Apple Intelligence state"
    @Published private(set) var foundationModelAdapterStatusLine = "Adapter status unknown"
    @Published private(set) var foundationModelPrivacyStatusLine = FoundationModelPrivacyLock.statusLine(
        requiresLocalOnly: UserDefaults.standard.object(forKey: CerberusSettingsKeys.requiresLocalFoundationModels) as? Bool ?? true
    )
    @Published private(set) var foundationModelProfile = "default"
    @Published private(set) var screenSnapshotStatusLine = "Screen snapshots not checked"
    @Published private(set) var screenSnapshotCount = 0
    @Published private(set) var fileSearchScopePaths: [String] = []
    @Published private var ambientToolAllowlist = ToolSessionAllowlist()
    @Published private var toolConfirmationOverrides: Set<String> = []
    @Published var selectedPanelSection: PanelSection = .session
    @Published var toolProfileID = ToolProfile.trustedDesk.id
    @Published var isAutoSilenceEnabled = true
    @Published var isVoiceConfirmationEnabled = true
    @Published var isSessionMemoryWriteDisabled = false {
        didSet {
            syncToolRegistryAllowlist()
            refreshAssistantToolPrompt()
        }
    }
    @Published var requiresConfirmationForAllTools = UserDefaults.standard.bool(forKey: CerberusSettingsKeys.requiresConfirmationForAllTools) {
        didSet {
            UserDefaults.standard.set(requiresConfirmationForAllTools, forKey: CerberusSettingsKeys.requiresConfirmationForAllTools)
        }
    }
    @Published var requiresLocalFoundationModels = UserDefaults.standard.object(forKey: CerberusSettingsKeys.requiresLocalFoundationModels) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(requiresLocalFoundationModels, forKey: CerberusSettingsKeys.requiresLocalFoundationModels)
            foundationModelPrivacyStatusLine = FoundationModelPrivacyLock.statusLine(requiresLocalOnly: requiresLocalFoundationModels)
            refreshConfiguredAdapter()
        }
    }
    @Published var usesConfiguredAdapter = UserDefaults.standard.object(forKey: CerberusSettingsKeys.usesConfiguredAdapter) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(usesConfiguredAdapter, forKey: CerberusSettingsKeys.usesConfiguredAdapter)
            refreshConfiguredAdapter()
        }
    }
    @Published var hotKeyConfigurationID = UserDefaults.standard.string(forKey: CerberusSettingsKeys.hotKeyConfigurationID) ?? HotKeyConfiguration.controlOptionSpace.id {
        didSet {
            UserDefaults.standard.set(hotKeyConfigurationID, forKey: CerberusSettingsKeys.hotKeyConfigurationID)
            hotKeyMonitor.update(configuration: hotKeyConfiguration)
        }
    }
    @Published var prefersSoundWakeWordClassifier = UserDefaults.standard.bool(forKey: CerberusSettingsKeys.prefersSoundWakeWordClassifier) {
        didSet {
            UserDefaults.standard.set(prefersSoundWakeWordClassifier, forKey: CerberusSettingsKeys.prefersSoundWakeWordClassifier)
            if isWakeWordEnabled {
                restartWakeWordMonitoring()
            } else {
                refreshWakeWordMonitorLine()
            }
        }
    }
    @Published var routesSpeechDirectlyToAirPods = UserDefaults.standard.bool(forKey: CerberusSettingsKeys.routesSpeechDirectlyToAirPods) {
        didSet {
            UserDefaults.standard.set(routesSpeechDirectlyToAirPods, forKey: CerberusSettingsKeys.routesSpeechDirectlyToAirPods)
            refreshPreferredSpeechOutputDevice()
        }
    }
    @Published var allowsMailBodySearch = UserDefaults.standard.bool(forKey: CerberusSettingsKeys.allowsMailBodySearch) {
        didSet {
            UserDefaults.standard.set(allowsMailBodySearch, forKey: CerberusSettingsKeys.allowsMailBodySearch)
            refreshAssistantToolPrompt()
        }
    }
    @Published var wakePhrase = UserDefaults.standard.string(forKey: CerberusSettingsKeys.wakePhrase) ?? "hey cerberus" {
        didSet {
            UserDefaults.standard.set(wakePhrase, forKey: CerberusSettingsKeys.wakePhrase)
        }
    }
    @Published var isWakeWordEnabled = false {
        didSet {
            if isWakeWordEnabled {
                startWakeWordMonitoringIfNeeded()
            } else {
                stopWakeWordMonitoring()
            }
        }
    }
    @Published var isMCPToolEnabled = false {
        didSet {
            refreshAssistantToolPrompt()
            if isMCPToolEnabled {
                startMCPHTTPListeners()
            } else {
                stopMCPHTTPListeners()
            }
        }
    }
    @Published var isShellToolEnabled = false {
        didSet {
            refreshAssistantToolPrompt()
        }
    }
    @Published var isShellProposalMode = UserDefaults.standard.object(forKey: CerberusSettingsKeys.shellProposalMode) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isShellProposalMode, forKey: CerberusSettingsKeys.shellProposalMode)
        }
    }
    @Published var headNodThreshold = 0.35 {
        didSet {
            updateHeadGestureThresholds()
        }
    }
    @Published var headShakeThreshold = 0.45 {
        didSet {
            updateHeadGestureThresholds()
        }
    }
    @Published var headGestureCooldownSeconds = UserDefaults.standard.object(forKey: CerberusSettingsKeys.headGestureCooldownSeconds) as? Double ?? defaultHeadGestureCooldownSeconds {
        didSet {
            let clamped = min(3.0, max(0.3, headGestureCooldownSeconds))
            if headGestureCooldownSeconds != clamped {
                headGestureCooldownSeconds = clamped
                return
            }
            UserDefaults.standard.set(headGestureCooldownSeconds, forKey: CerberusSettingsKeys.headGestureCooldownSeconds)
            updateHeadGestureThresholds()
        }
    }
    @Published var isHeadGestureValidationLoggingEnabled = false
    @Published var transcriptDraft = ""
    @Published var mcpClientDraft = ""
    @Published var mcpElicitationFieldDrafts: [MCPClientElicitationFieldDraft] = []

    private let permissionCenter = PermissionCenter()
    private let transcriber: any AppTranscribing
    private let wakeWordTranscriber: any AppTranscribing
    private let wakeWordSoundClassifier = WakeWordSoundClassifier()
    private let speaker: any AppSpeaking
    private let earconPlayer = EarconPlayer()
    private let hotKeyMonitor = GlobalHotKeyMonitor()
    private let headGestureDetector = HeadGestureDetector()
    private let headGestureValidationLog = HeadGestureValidationLog()
    private let mediaKeyInterceptor = MediaKeyInterceptor()
    private let fileSearchScopeStore: FileSearchScopeStore
    private let toolRegistry: ToolRegistry
    private let confirmationGate = ConfirmationGate()
    private let auditLog: AuditLog
    private let assistant: any AppAssistanting
    private let baseReadOnlyNativeTools: [any FoundationModels.Tool]
    private let transcriptStore = EncryptedTranscriptStore()
    private let memoryStore = EncryptedMemoryStore()
    private let telemetryStore = LocalTelemetryStore()
    private let adapterLoader = FoundationModelAdapterLoader()
    private let foundationModelStatusProvider = FoundationModelAvailabilityStatusProvider()
    private let taskNotificationPolicy = LongRunningTaskNotificationPolicy()
    private let taskNotificationScheduler: any LocalTaskNotificationScheduling = UserNotificationTaskScheduler()
    private let skipsFoundationModelAvailabilityCheck: Bool
    private let mcpServerRegistry: MCPServerRegistry
    private let mcpClientRequestBroker: MCPClientRequestBroker
    private let mcpNativeToolLoader: MCPNativeToolLoader
    private var audioOutputRouteMonitor: AudioOutputRouteMonitor?
    private var pendingPlan: AssistantPlan?
    private var activeRequest: String?
    private var recentTransitionHistory = RecentTransitionHistory()
    private var pendingMCPDecisionContinuation: CheckedContinuation<MCPClientRequestDecision, Never>?
    private var mcpListenerSetupTask: Task<Void, Never>?
    private var mcpListenerTasks: [Task<Void, Never>] = []
    private var mcpListenerLastEventIDs: [String: String] = [:]
    private var mcpServerHealthStates: [String: MCPServerHealthState] = [:]
    private var mcpServerHealthDetails: [String: String] = [:]
    private var adapterFailureCircuitBreaker = AdapterFailureCircuitBreaker()
    private var silenceTask: Task<Void, Never>?
    private var confirmationVoiceTimeoutTask: Task<Void, Never>?
    private let delayedTaskScheduler = DelayedTaskScheduler()
    private let silenceTimeoutNanoseconds: UInt64 = 1_500_000_000
    private let confirmationVoiceTimeoutNanoseconds: UInt64 = 8_000_000_000
    private static let ambientToolSummaries = DefaultToolCatalog.summaries
    private static let mcpToolSummaries = makeMCPTools(clientRequestHandlers: .none).map(\.summary)
    private static let shellToolSummary = ShellTool().summary

    private static func shellXPCBundleURL() -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("XPCServices", isDirectory: true)
            .appendingPathComponent("ShellExecService.xpc", isDirectory: true)
    }

    private static func makeMCPTools(clientRequestHandlers: MCPClientRequestHandlers) -> [AnyAssistantTool] {
        [
            AnyAssistantTool(MCPTool(runner: MCPConfiguredToolRunner(clientRequestHandlers: clientRequestHandlers))),
            AnyAssistantTool(MCPResourceListTool(runner: MCPConfiguredResourceRunner(clientRequestHandlers: clientRequestHandlers))),
            AnyAssistantTool(MCPResourceReadTool(runner: MCPConfiguredResourceRunner(clientRequestHandlers: clientRequestHandlers))),
            AnyAssistantTool(MCPPromptListTool(runner: MCPConfiguredPromptRunner(clientRequestHandlers: clientRequestHandlers))),
            AnyAssistantTool(MCPPromptGetTool(runner: MCPConfiguredPromptRunner(clientRequestHandlers: clientRequestHandlers))),
            AnyAssistantTool(MCPOAuthDiscoverTool()),
            AnyAssistantTool(MCPOAuthStartTool()),
            AnyAssistantTool(MCPOAuthExchangeTool()),
            AnyAssistantTool(MCPOAuthRefreshTool()),
            AnyAssistantTool(MCPOAuthAuthorizeLocalTool())
        ]
    }

    init(
        transcriber: any AppTranscribing = Transcriber(),
        wakeWordTranscriber: any AppTranscribing = Transcriber(),
        speaker: any AppSpeaking = Speaker(),
        assistant injectedAssistant: (any AppAssistanting)? = nil,
        toolRegistry injectedToolRegistry: ToolRegistry? = nil,
        auditLog injectedAuditLog: AuditLog = AuditLog(),
        startsRuntimeServices: Bool = true,
        skipsFoundationModelAvailabilityCheck: Bool = false
    ) {
        let mcpClientRequestBroker = MCPClientRequestBroker()
        let mcpServerRegistry = MCPServerRegistry()
        let fileSearchScopeStore = FileSearchScopeStore()
        let fileSearchTool = FileSearchTool(approvedScopePathsProvider: { fileSearchScopeStore.approvedScopePaths() })
        let mailSearchTool = MailSearchTool(
            allowBodySearch: {
                UserDefaults.standard.bool(forKey: CerberusSettingsKeys.allowsMailBodySearch)
            }
        )
        let shellTool = ShellTool(
            allowExecution: true,
            forceDryRun: {
                UserDefaults.standard.object(forKey: CerberusSettingsKeys.shellProposalMode) as? Bool ?? true
            },
            executor: ShellXPCCommandExecutor(serviceBundleURL: Self.shellXPCBundleURL())
        )
        let mcpTools = Self.makeMCPTools(clientRequestHandlers: mcpClientRequestBroker.handlers)
        let tools = DefaultToolCatalog.makeTools(fileSearchTool: fileSearchTool, mailSearchTool: mailSearchTool) + mcpTools + [AnyAssistantTool(shellTool)]
        let baseReadOnlyNativeTools = DefaultToolCatalog.readOnlyFoundationModelTools(
            auditLog: injectedAuditLog,
            fileSearchTool: fileSearchTool,
            mailSearchTool: mailSearchTool
        )
        self.mcpClientRequestBroker = mcpClientRequestBroker
        self.mcpServerRegistry = mcpServerRegistry
        self.fileSearchScopeStore = fileSearchScopeStore
        self.auditLog = injectedAuditLog
        self.transcriber = transcriber
        self.wakeWordTranscriber = wakeWordTranscriber
        self.speaker = speaker
        self.mcpNativeToolLoader = MCPNativeToolLoader(
            registry: mcpServerRegistry,
            clientRequestHandlers: mcpClientRequestBroker.handlers,
            auditLog: injectedAuditLog
        )
        self.baseReadOnlyNativeTools = baseReadOnlyNativeTools
        self.skipsFoundationModelAvailabilityCheck = skipsFoundationModelAvailabilityCheck
        toolRegistry = injectedToolRegistry ?? ((try? ToolRegistry(tools: tools)) ?? ToolRegistry())
        assistant = injectedAssistant ?? Assistant(
            toolSummaries: Self.ambientToolSummaries,
            readOnlyNativeTools: baseReadOnlyNativeTools
        )
        mcpClientRequestBroker.model = self
        fileSearchScopePaths = fileSearchScopeStore.approvedScopePaths()
        refreshPermissions()
        refreshAudioOutputRoute()
        refreshWakeWordMonitorLine()
        refreshFoundationModelStatus()
        refreshScreenSnapshotStatus()
        refreshMCPServerHealthStatus()
        if startsRuntimeServices {
            startAudioOutputRouteMonitor()
        }
        refreshAuditEntries()
        hotKeyMonitor.update(configuration: hotKeyConfiguration)
        updateHeadGestureThresholds()
        if startsRuntimeServices {
            startTriggers()
        }
        refreshConfiguredAdapter()
    }

    deinit {
        audioOutputRouteMonitor?.stop()
    }

    var state: AssistantState {
        stateMachine.state
    }

    var isMicrophoneActive: Bool {
        state.isMicrophoneActive || isConfirmationVoiceActive || isWakeWordMonitoring
    }

    var nextPermissionSnapshot: PermissionSnapshot? {
        permissionSnapshots.first { $0.state != .granted }
    }

    var shouldShowOnboarding: Bool {
        !hasSkippedOnboarding && nextPermissionSnapshot != nil
    }

    var grantedPermissionCount: Int {
        permissionSnapshots.filter { $0.state == .granted }.count
    }

    var setupChecklistSummary: String {
        let permissionNames = permissionSnapshots.map(\.kind.displayName).joined(separator: ", ")
        return "\(grantedPermissionCount) permissions ready: \(permissionNames)"
    }

    var enabledToolDisplayText: String {
        let labels = enabledToolSummaries.map(\.name)
        return labels.isEmpty ? "none" : labels.joined(separator: ", ")
    }

    var availableAmbientToolSummaries: [ToolSummary] {
        Self.ambientToolSummaries
    }

    var toolProfiles: [ToolProfile] {
        ToolProfile.allCases
    }

    var disabledAmbientToolCount: Int {
        ambientToolAllowlist.disabledToolNames.count
    }

    var toolConfirmationOverrideCount: Int {
        toolConfirmationOverrides.count
    }

    var hotKeyPresets: [HotKeyConfiguration] {
        HotKeyConfiguration.presets
    }

    var hotKeyConfiguration: HotKeyConfiguration {
        HotKeyConfiguration.preset(id: hotKeyConfigurationID)
    }

    var appDataLocations: [AppDataLocation] {
        [
            AppDataLocation(name: "Audit log", url: AuditLog.defaultFileURL()),
            AppDataLocation(name: "Transcripts", url: EncryptedTranscriptStore.defaultFileURL()),
            AppDataLocation(name: "Memories", url: EncryptedMemoryStore.defaultFileURL()),
            AppDataLocation(name: "Telemetry", url: LocalTelemetryStore.defaultFileURL()),
            AppDataLocation(name: "Wake samples", url: WakeWordSampleDataset.defaultDirectoryURL()),
            AppDataLocation(name: "Adapter config", url: FoundationModelAdapterLoader.defaultFileURL()),
            AppDataLocation(name: "MCP config", url: MCPServerRegistry.defaultFileURL()),
            AppDataLocation(name: "Screen snapshots", url: ScreenSnapshotTool.defaultOutputDirectoryURL())
        ]
    }

    func isAmbientToolEnabled(_ toolName: String) -> Bool {
        ambientToolAllowlist.isEnabled(toolName)
    }

    func requiresConfirmationOverride(_ toolName: String) -> Bool {
        toolConfirmationOverrides.contains(toolName)
    }

    func setConfirmationOverride(_ toolName: String, requiresConfirmation: Bool) {
        if requiresConfirmation {
            toolConfirmationOverrides.insert(toolName)
        } else {
            toolConfirmationOverrides.remove(toolName)
        }
    }

    func resetConfirmationOverrides() {
        toolConfirmationOverrides.removeAll()
    }

    func setAmbientTool(_ toolName: String, enabled: Bool) {
        var allowlist = ambientToolAllowlist
        allowlist.setEnabled(toolName, enabled: enabled)
        ambientToolAllowlist = allowlist
        syncToolRegistryAllowlist()
        refreshAssistantToolPrompt()
    }

    func resetAmbientToolAllowlist() {
        ambientToolAllowlist = ToolSessionAllowlist()
        syncToolRegistryAllowlist()
        refreshAssistantToolPrompt()
    }

    func applyToolProfile(id: String) {
        let profile = ToolProfile.profile(id: id)
        let configuration = profile.configuration(ambientSummaries: Self.ambientToolSummaries)
        toolProfileID = profile.id
        ambientToolAllowlist = ToolSessionAllowlist(disabledToolNames: configuration.disabledAmbientToolNames)
        requiresConfirmationForAllTools = configuration.requiresConfirmationForAllTools
        isMCPToolEnabled = configuration.mcpEnabled
        isShellToolEnabled = configuration.shellEnabled
        syncToolRegistryAllowlist()
        refreshAssistantToolPrompt()
    }

    func isMCPServerEnabled(_ serverName: String) -> Bool {
        mcpServerHealthLines.first { $0.name == serverName }?.serverEnabled ?? false
    }

    func setMCPServer(_ serverName: String, enabled: Bool) {
        Task {
            do {
                try await mcpServerRegistry.setEnabled(enabled, for: serverName)
                await mcpServerRegistry.reload()
                if isMCPToolEnabled {
                    startMCPHTTPListeners()
                } else {
                    refreshMCPServerHealthStatus()
                }
                refreshAssistantToolPrompt()
            } catch {
                statusLine = error.localizedDescription
            }
        }
    }

    func revealAppDataLocation(_ location: AppDataLocation) {
        let url = location.url
        let revealURL = FileManager.default.fileExists(atPath: url.path)
            ? url
            : url.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([revealURL])
    }

    func refreshScreenSnapshotStatus() {
        let directoryURL = ScreenSnapshotTool.defaultOutputDirectoryURL()
        screenSnapshotCount = ScreenSnapshotCache.snapshotCount(in: directoryURL)
        screenSnapshotStatusLine = screenSnapshotCount == 1
            ? "1 cached snapshot in \(directoryURL.path)"
            : "\(screenSnapshotCount) cached snapshots in \(directoryURL.path)"
    }

    func openLatestScreenSnapshot() {
        let directoryURL = ScreenSnapshotTool.defaultOutputDirectoryURL()
        guard let fileURL = ScreenSnapshotCache.latestSnapshotURL(in: directoryURL) else {
            statusLine = "No screen snapshots found."
            refreshScreenSnapshotStatus()
            return
        }

        NSWorkspace.shared.open(fileURL)
        statusLine = "Opened latest screen snapshot."
        screenSnapshotStatusLine = "Latest snapshot: \(fileURL.path)"
    }

    func deleteScreenSnapshots() {
        do {
            let count = try ScreenSnapshotCache.deleteSnapshots(in: ScreenSnapshotTool.defaultOutputDirectoryURL())
            screenSnapshotCount = 0
            screenSnapshotStatusLine = count == 1 ? "Deleted 1 screen snapshot." : "Deleted \(count) screen snapshots."
            statusLine = screenSnapshotStatusLine
        } catch {
            statusLine = error.localizedDescription
        }
    }

    func addFileSearchScope() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders cerberus may search by filename."

        guard panel.runModal() == .OK else {
            return
        }

        do {
            for url in panel.urls {
                try fileSearchScopeStore.add(url.path)
            }
            fileSearchScopePaths = fileSearchScopeStore.approvedScopePaths()
            statusLine = fileSearchScopePaths.isEmpty ? "No file search folders approved." : "File search folders updated."
        } catch {
            statusLine = error.localizedDescription
        }
    }

    func removeFileSearchScope(_ path: String) {
        fileSearchScopePaths = fileSearchScopeStore.remove(path)
        statusLine = fileSearchScopePaths.isEmpty ? "No file search folders approved." : "File search folders updated."
    }

    var menuBarSystemImage: String {
        switch state {
        case .idle:
            "circle"
        case .listening:
            "record.circle"
        case .reasoning:
            "brain"
        case .awaitingConfirm:
            "exclamationmark.circle"
        case .executing:
            "terminal"
        case .speaking:
            "waveform"
        }
    }

    func startListening(trigger: WakeTrigger = .manual) {
        if state == .speaking {
            cancel(restartWakeWord: false)
        }

        Task {
            await stopWakeWordMonitoringAndWait()
            if apply(.wakeDetected(trigger)) {
                startVoiceCapture()
            }
        }
    }

    func finishListeningAndProcess() {
        silenceTask?.cancel()
        silenceTask = nil

        Task {
            await transcriber.stop()
            let request = transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !request.isEmpty else {
                finishListeningWithDraft()
                return
            }

            apply(.silenceDetected)
            await runReasoning(for: request)
        }
    }

    private func finishListeningWithDraft() {
        guard !transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            apply(.cancelRequested)
            return
        }
        apply(.silenceDetected)
    }

    func finishSpeaking() {
        transcriptDraft = ""
        activeRequest = nil
        apply(.speechFinished)
        startWakeWordMonitoringIfNeeded()
    }

    func cancel() {
        cancel(restartWakeWord: true)
    }

    private func cancel(restartWakeWord: Bool) {
        transcriptDraft = ""
        activeRequest = nil
        silenceTask?.cancel()
        silenceTask = nil
        stopConfirmationVoiceCapture()
        Task {
            await transcriber.cancel()
        }
        speaker.stop()
        clearPendingConfirmation()
        finishMCPClientRequest(.cancel)
        apply(.cancelRequested)
        if restartWakeWord {
            startWakeWordMonitoringIfNeeded()
        }
    }

    func reset() {
        transcriptDraft = ""
        activeRequest = nil
        silenceTask?.cancel()
        silenceTask = nil
        stopConfirmationVoiceCapture()
        Task {
            await transcriber.cancel()
        }
        speaker.stop()
        clearPendingConfirmation()
        finishMCPClientRequest(.cancel)
        apply(.reset)
        startWakeWordMonitoringIfNeeded()
    }

    func refreshPermissions() {
        permissionSnapshots = permissionCenter.currentSnapshots()
    }

    func refreshAudioOutputRoute() {
        do {
            let device = try AudioOutputRouteInspector.defaultOutputDevice()
            audioOutputRouteLine = device.displayName
            isAudioOutputLikelyAirPods = device.isLikelyAirPods
        } catch {
            audioOutputRouteLine = error.localizedDescription
            isAudioOutputLikelyAirPods = false
        }
        refreshPreferredSpeechOutputDevice()
    }

    func refreshFoundationModelStatus() {
        foundationModelAvailabilityLine = foundationModelStatusProvider.statusLine()
        foundationModelAvailabilityDetailLine = foundationModelStatusProvider.diagnosticText()
    }

    private func refreshPreferredSpeechOutputDevice() {
        guard routesSpeechDirectlyToAirPods else {
            speaker.setPreferredOutputDevice(nil)
            speechOutputRoutingLine = "Speech follows system output"
            return
        }

        do {
            guard let device = try AudioOutputRouteInspector.preferredAirPodsOutputDevice() else {
                speaker.setPreferredOutputDevice(nil)
                speechOutputRoutingLine = "Direct AirPods route unavailable"
                return
            }
            speaker.setPreferredOutputDevice(device)
            speechOutputRoutingLine = "Direct target: \(device.displayName)"
        } catch {
            speaker.setPreferredOutputDevice(nil)
            speechOutputRoutingLine = error.localizedDescription
        }
    }

    private func startAudioOutputRouteMonitor() {
        let monitor = AudioOutputRouteMonitor { [weak self] in
            Task { @MainActor in
                self?.refreshAudioOutputRoute()
            }
        }
        do {
            try monitor.start()
            audioOutputRouteMonitor = monitor
        } catch {
            statusLine = error.localizedDescription
        }
    }

    func refreshTranscriptRecords() {
        Task {
            do {
                transcriptRecords = try await transcriptStore.records()
                    .sorted { $0.timestamp > $1.timestamp }
            } catch {
                statusLine = error.localizedDescription
            }
        }
    }

    func exportTranscriptRecords() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "cerberus-transcripts.json"
        panel.prompt = "Export"
        panel.message = "Export decrypted transcript history as JSON."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        Task {
            do {
                try await transcriptStore.exportPlaintextJSON(to: url)
                statusLine = "Exported transcript history to \(url.path)"
            } catch {
                statusLine = error.localizedDescription
            }
        }
    }

    func deleteTranscriptRecords() {
        let alert = NSAlert()
        alert.messageText = "Delete transcript history?"
        alert.informativeText = "This removes encrypted transcript history stored by cerberus."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            do {
                try await transcriptStore.deleteAll()
                transcriptRecords = []
                statusLine = "Deleted transcript history."
            } catch {
                statusLine = error.localizedDescription
            }
        }
    }

    func refreshMemoryRecords() {
        Task {
            do {
                memoryRecords = try await memoryStore.records()
                    .sorted { $0.timestamp > $1.timestamp }
            } catch {
                statusLine = error.localizedDescription
            }
        }
    }

    func exportMemoryRecords() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "cerberus-memories.json"
        panel.prompt = "Export"
        panel.message = "Export decrypted memory records as JSON."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        Task {
            do {
                try await memoryStore.exportPlaintextJSON(to: url)
                statusLine = "Exported memories to \(url.path)"
            } catch {
                statusLine = error.localizedDescription
            }
        }
    }

    func deleteMemoryRecords() {
        let alert = NSAlert()
        alert.messageText = "Delete memories?"
        alert.informativeText = "This removes encrypted memory records stored by cerberus."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            do {
                try await memoryStore.deleteAll()
                memoryRecords = []
                statusLine = "Deleted memories."
            } catch {
                statusLine = error.localizedDescription
            }
        }
    }

    func exportDiagnosticsBundle() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "cerberus-diagnostics.json"
        panel.prompt = "Export"
        panel.message = "Export redacted diagnostics as JSON."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        Task {
            do {
                let locations = appDataLocations.map {
                    DiagnosticBundleAppDataLocation(
                        name: $0.name,
                        path: $0.url.path,
                        exists: FileManager.default.fileExists(atPath: $0.url.path)
                    )
                }
                let snapshot = DiagnosticBundleSnapshot(
                    statusLines: [
                        statusLine,
                        foundationModelAvailabilityLine,
                        foundationModelAvailabilityDetailLine,
                        foundationModelAdapterStatusLine,
                        wakeWordMonitorLine,
                        mcpListenerStatusLine,
                        screenSnapshotStatusLine,
                        audioOutputRouteLine,
                        speechOutputRoutingLine
                    ],
                    appDataLocations: locations,
                    auditEntries: try await auditLog.entries(),
                    telemetryRecords: try await telemetryStore.records()
                )
                try DiagnosticBundleExporter().write(snapshot, to: url)
                statusLine = "Exported diagnostics to \(url.path)"
            } catch {
                statusLine = error.localizedDescription
            }
        }
    }

    func refreshAuditEntries() {
        Task {
            do {
                recentAuditEntries = try await auditLog.recentEntries(limit: 5)
            } catch {
                statusLine = error.localizedDescription
            }
        }
    }

    func deleteAuditEntries() {
        let alert = NSAlert()
        alert.messageText = "Clear tool call history?"
        alert.informativeText = "This removes the local audit history displayed by cerberus."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task {
            do {
                try await auditLog.deleteAll()
                recentAuditEntries = []
                statusLine = "Cleared tool call history."
            } catch {
                statusLine = error.localizedDescription
            }
        }
    }

    func answerLastToolAction() {
        Task {
            let summary = await lastToolActionSummary()
            statusLine = summary
            speaker.speak(summary) { [weak self] in
                self?.finishSpeaking()
            }
        }
    }

    func requestPermission(_ kind: SystemPermission) {
        Task {
            let snapshot = await permissionCenter.request(kind)
            replacePermissionSnapshot(snapshot)
        }
    }

    func requestNextPermission() {
        guard let nextPermissionSnapshot else {
            return
        }
        requestPermission(nextPermissionSnapshot.kind)
    }

    func skipOnboarding() {
        hasSkippedOnboarding = true
        UserDefaults.standard.set(true, forKey: CerberusSettingsKeys.onboardingSkipped)
    }

    func resetOnboarding() {
        hasSkippedOnboarding = false
        UserDefaults.standard.set(false, forKey: CerberusSettingsKeys.onboardingSkipped)
        refreshPermissions()
    }

    func calibrateHeadGestures() {
        statusLine = headGestureDetector.calibrate()
            ? "Head gesture neutral pose calibrated."
            : "No AirPods motion sample is available yet."
    }

    func resetHeadGestureThresholds() {
        headNodThreshold = 0.35
        headShakeThreshold = 0.45
        headGestureCooldownSeconds = defaultHeadGestureCooldownSeconds
        updateHeadGestureThresholds()
    }

    func exportHeadGestureThresholdProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "cerberus-head-gesture-profile.json"
        panel.prompt = "Export"
        panel.message = "Export AirPods gesture thresholds as JSON."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let profile = try HeadGestureThresholdProfile(
                nodThreshold: headNodThreshold,
                shakeThreshold: headShakeThreshold,
                cooldownSeconds: headGestureCooldownSeconds
            )
            try profile.write(to: url)
            statusLine = "Exported AirPods gesture profile to \(url.path)"
        } catch {
            statusLine = error.localizedDescription
        }
    }

    func importHeadGestureThresholdProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose a cerberus AirPods gesture profile JSON file."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let profile = try HeadGestureThresholdProfile.read(from: url)
            headNodThreshold = profile.nodThreshold
            headShakeThreshold = profile.shakeThreshold
            headGestureCooldownSeconds = profile.cooldownSeconds
            updateHeadGestureThresholds()
            statusLine = "Imported AirPods gesture profile from \(url.path)"
        } catch {
            statusLine = error.localizedDescription
        }
    }

    func approvePendingConfirmation() {
        stopConfirmationVoiceCapture()
        Task {
            guard let pendingConfirmation,
                  await confirmationGate.accept(id: pendingConfirmation.id),
                  let plan = pendingPlan else {
                return
            }

            self.pendingConfirmation = nil
            pendingPlan = nil
            apply(.confirmationAccepted)
            await execute(plan, confirmed: true, transitionToExecuting: false)
        }
    }

    func denyPendingConfirmation() {
        stopConfirmationVoiceCapture()
        Task {
            guard let pendingConfirmation else {
                return
            }

            _ = await confirmationGate.deny(id: pendingConfirmation.id)
            self.pendingConfirmation = nil
            pendingPlan = nil
            activeRequest = nil
            apply(.confirmationDenied)
            speaker.speak("Cancelled.")
        }
    }

    func approveMCPClientRequest() {
        if pendingMCPClientRequest?.kind == .elicitation, !mcpElicitationFieldDrafts.isEmpty {
            do {
                finishMCPClientRequest(.approve(try Self.elicitationContentJSON(from: mcpElicitationFieldDrafts)))
            } catch {
                statusLine = error.localizedDescription
            }
            return
        }

        finishMCPClientRequest(.approve(mcpClientDraft))
    }

    func declineMCPClientRequest() {
        finishMCPClientRequest(.decline)
    }

    func cancelMCPClientRequest() {
        finishMCPClientRequest(.cancel)
    }

    func handleMCPSamplingRequest(_ request: MCPSamplingRequest) async throws -> MCPSamplingResponse {
        let promptDraft = request.messagesText.isEmpty ? request.rawParamsJSON : request.messagesText
        let promptDecision = await requestMCPClientDecision(
            PendingMCPClientRequest(
                kind: .samplingPrompt,
                serverName: request.serverName,
                summary: "Server \(request.serverName) requested a nested model completion.",
                detail: request.systemPrompt ?? "No server system prompt."
            ),
            draft: promptDraft
        )
        guard case let .approve(approvedPrompt) = promptDecision else {
            throw ToolExecutionError.denied("MCP sampling request was not approved.")
        }

        statusLine = "MCP sampling running."
        let generated = try await assistant.sampleForMCP(
            messagesText: approvedPrompt,
            systemPrompt: request.systemPrompt
        )
        let responseDecision = await requestMCPClientDecision(
            PendingMCPClientRequest(
                kind: .samplingResponse,
                serverName: request.serverName,
                summary: "Review the response before returning it to \(request.serverName).",
                detail: "Model: cerberus"
            ),
            draft: generated
        )
        guard case let .approve(approvedResponse) = responseDecision else {
            throw ToolExecutionError.denied("MCP sampling response was not approved.")
        }

        return MCPSamplingResponse(text: approvedResponse)
    }

    func handleMCPElicitationRequest(_ request: MCPElicitationRequest) async throws -> MCPElicitationResponse {
        let decision = await requestMCPClientDecision(
            PendingMCPClientRequest(
                kind: .elicitation,
                serverName: request.serverName,
                summary: request.message,
                detail: request.schemaJSON
            ),
            draft: Self.defaultElicitationDraft(for: request),
            elicitationFieldDrafts: Self.defaultElicitationFieldDrafts(for: request)
        )

        switch decision {
        case let .approve(contentJSON):
            return MCPElicitationResponse(action: .accept, contentJSON: contentJSON)
        case .decline:
            return MCPElicitationResponse(action: .decline)
        case .cancel:
            return MCPElicitationResponse(action: .cancel)
        }
    }

    @discardableResult
    private func apply(_ event: AssistantEvent) -> Bool {
        guard let transition = stateMachine.handle(event) else {
            return false
        }

        statusLine = transition.message ?? transition.to.displayName
        recentEvents = recentTransitionHistory.record(transition)
        earconPlayer.play(for: transition)
        return true
    }

    private func startTriggers() {
        hotKeyMonitor.start { [weak self] in
            self?.startListening(trigger: .hotKey)
        }

        headGestureDetector.start { [weak self] gesture in
            guard let self else {
                return
            }

            switch gesture {
            case .nod:
                if state == .awaitingConfirm {
                    approvePendingConfirmation()
                } else {
                    startListening(trigger: .headNod)
                }
            case .shake:
                if state == .awaitingConfirm {
                    denyPendingConfirmation()
                }
            }
        } onSample: { [weak self] snapshot in
            self?.recordHeadGestureSnapshot(snapshot)
        }

        _ = mediaKeyInterceptor.start { [weak self] trigger in
            guard let self else {
                return
            }

            switch trigger {
            case .singlePress:
                if state == .awaitingConfirm {
                    denyPendingConfirmation()
                } else if state == .listening || state == .speaking {
                    cancel()
                }
            case .triplePress:
                startListening(trigger: .stemTriplePress)
            }
        }
    }

    private func updateHeadGestureThresholds() {
        headGestureDetector.updateThresholds(
            pitch: headNodThreshold,
            yaw: headShakeThreshold,
            cooldown: headGestureCooldownSeconds
        )
    }

    private func recordHeadGestureSnapshot(_ snapshot: HeadGestureMotionSnapshot) {
        guard isHeadGestureValidationLoggingEnabled else {
            return
        }
        Task {
            do {
                try await headGestureValidationLog.append(snapshot)
            } catch {
                await MainActor.run {
                    statusLine = error.localizedDescription
                }
            }
        }
    }

    private func startVoiceCapture() {
        Task {
            do {
                try await transcriber.start { [weak self] update in
                    self?.handleTranscriptionUpdate(update)
                }
            } catch {
                apply(.failed(error.localizedDescription))
                speaker.speak(error.localizedDescription) { [weak self] in
                    self?.finishSpeaking()
                }
            }
        }
    }

    private func handleTranscriptionUpdate(_ update: TranscriptionUpdate) {
        transcriptDraft = update.text
        scheduleSilenceTimeoutIfNeeded()
    }

    private func startWakeWordMonitoringIfNeeded() {
        guard isWakeWordEnabled,
              state == .idle,
              !isWakeWordMonitoring,
              !transcriber.isRunning,
              !wakeWordTranscriber.isRunning,
              !wakeWordSoundClassifier.isRunning else {
            return
        }

        if prefersSoundWakeWordClassifier, startSoundWakeWordMonitoringIfConfigured() {
            return
        }

        startSpeechWakeWordMonitoring()
    }

    private func startSpeechWakeWordMonitoring() {
        isWakeWordMonitoring = true
        wakeWordMonitorLine = WakeWordMonitorStatusLine.speechTranscription
        statusLine = "Wake phrase armed."
        Task {
            do {
                try await wakeWordTranscriber.start { [weak self] update in
                    self?.handleWakeWordUpdate(update)
                }
            } catch {
                isWakeWordMonitoring = false
                refreshWakeWordMonitorLine()
                statusLine = error.localizedDescription
            }
        }
    }

    private func startSoundWakeWordMonitoringIfConfigured() -> Bool {
        let configuration: WakeWordSoundClassifierConfiguration
        do {
            guard let loadedConfiguration = try WakeWordSoundClassifierConfigurationLoader.loadIfPresent() else {
                wakeWordMonitorLine = WakeWordMonitorStatusLine.soundModelConfigMissingUsingSpeechPhrase
                return false
            }
            configuration = loadedConfiguration
        } catch {
            wakeWordMonitorLine = error.localizedDescription
            return false
        }

        isWakeWordMonitoring = true
        wakeWordMonitorLine = WakeWordMonitorStatusLine.soundModelArmed
        statusLine = "Wake sound model armed."
        Task {
            do {
                try await wakeWordSoundClassifier.start(configuration: configuration) { [weak self] classifications in
                    self?.handleWakeWordSoundDetection(classifications)
                }
            } catch {
                isWakeWordMonitoring = false
                wakeWordMonitorLine = error.localizedDescription
                startSpeechWakeWordMonitoring()
            }
        }
        return true
    }

    private func handleWakeWordUpdate(_ update: TranscriptionUpdate) {
        guard isWakeWordMonitoring,
              state == .idle,
              WakeWordDetector(phrases: [wakePhrase]).detectsWakeWord(in: update.text) else {
            return
        }

        Task {
            await stopWakeWordMonitoringAndWait()
            startListening(trigger: .wakeWord)
        }
    }

    private func handleWakeWordSoundDetection(_ classifications: [WakeWordSoundClassification]) {
        guard isWakeWordMonitoring, state == .idle else {
            return
        }

        let topClassification = classifications.max { $0.confidence < $1.confidence }
        wakeWordMonitorLine = topClassification.map {
            WakeWordMonitorStatusLine.soundMatched(identifier: $0.identifier, confidence: $0.confidence)
        } ?? WakeWordMonitorStatusLine.soundMatched

        Task {
            await stopWakeWordMonitoringAndWait()
            startListening(trigger: .wakeWord)
        }
    }

    private func stopWakeWordMonitoring() {
        guard isWakeWordMonitoring || wakeWordTranscriber.isRunning || wakeWordSoundClassifier.isRunning else {
            return
        }

        isWakeWordMonitoring = false
        Task {
            await wakeWordTranscriber.cancel()
            wakeWordSoundClassifier.cancel()
            refreshWakeWordMonitorLine()
        }
    }

    private func stopWakeWordMonitoringAndWait() async {
        guard isWakeWordMonitoring || wakeWordTranscriber.isRunning || wakeWordSoundClassifier.isRunning else {
            return
        }

        isWakeWordMonitoring = false
        await wakeWordTranscriber.cancel()
        wakeWordSoundClassifier.cancel()
        refreshWakeWordMonitorLine()
    }

    private func restartWakeWordMonitoring() {
        Task {
            await stopWakeWordMonitoringAndWait()
            startWakeWordMonitoringIfNeeded()
        }
    }

    private func refreshWakeWordMonitorLine() {
        if prefersSoundWakeWordClassifier {
            let configURL = WakeWordSoundClassifierConfigurationLoader.defaultFileURL()
            if FileManager.default.fileExists(atPath: configURL.path) {
                wakeWordMonitorLine = WakeWordMonitorStatusLine.soundModelConfigured
            } else {
                wakeWordMonitorLine = WakeWordMonitorStatusLine.soundModelConfigMissing
            }
        } else {
            wakeWordMonitorLine = WakeWordMonitorStatusLine.speechTranscription
        }
    }

    private func scheduleSilenceTimeoutIfNeeded() {
        silenceTask?.cancel()

        guard state == .listening,
              isAutoSilenceEnabled,
              !transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            silenceTask = nil
            return
        }

        let timeout = silenceTimeoutNanoseconds
        silenceTask = delayedTaskScheduler.schedule(afterNanoseconds: timeout) { [weak self] in
            await MainActor.run {
                self?.finishListeningAndProcess()
            }
        }
    }

    private func startConfirmationVoiceCapture() {
        guard state == .awaitingConfirm,
              pendingConfirmation != nil,
              isVoiceConfirmationEnabled,
              !isConfirmationVoiceActive else {
            return
        }

        isConfirmationVoiceActive = true
        statusLine = "Say yes to approve or no to cancel."
        scheduleConfirmationVoiceTimeout()

        Task {
            do {
                try await transcriber.start { [weak self] update in
                    self?.handleConfirmationTranscription(update)
                }
            } catch {
                isConfirmationVoiceActive = false
                confirmationVoiceTimeoutTask?.cancel()
                confirmationVoiceTimeoutTask = nil
                statusLine = error.localizedDescription
            }
        }
    }

    private func handleConfirmationTranscription(_ update: TranscriptionUpdate) {
        guard isConfirmationVoiceActive,
              let decision = VoiceConfirmationParser.decision(in: update.text) else {
            return
        }

        isConfirmationVoiceActive = false
        confirmationVoiceTimeoutTask?.cancel()
        confirmationVoiceTimeoutTask = nil

        Task {
            await transcriber.stop()
            switch decision {
            case .accept:
                approvePendingConfirmation()
            case .deny:
                denyPendingConfirmation()
            }
        }
    }

    private func scheduleConfirmationVoiceTimeout() {
        confirmationVoiceTimeoutTask?.cancel()
        let timeout = confirmationVoiceTimeoutNanoseconds
        confirmationVoiceTimeoutTask = delayedTaskScheduler.schedule(afterNanoseconds: timeout) { [weak self] in
            await MainActor.run {
                self?.stopConfirmationVoiceCapture()
            }
        }
    }

    private func stopConfirmationVoiceCapture() {
        confirmationVoiceTimeoutTask?.cancel()
        confirmationVoiceTimeoutTask = nil
        guard isConfirmationVoiceActive else {
            return
        }

        isConfirmationVoiceActive = false
        Task {
            await transcriber.cancel()
        }
    }

    private func runReasoning(for request: String) async {
        do {
            activeRequest = request
            if await answerAuditQuestionIfNeeded(request) {
                return
            }
            guard skipsFoundationModelAvailabilityCheck || foundationModelStatusProvider.isAvailable() else {
                refreshFoundationModelStatus()
                speak(foundationModelStatusProvider.fallbackText())
                return
            }
            let activeApplicationName = currentActiveApplicationName()
            let context = AssistantContext(
                activeApplicationName: activeApplicationName,
                allowedToolNames: enabledToolNames,
                fileSearchScopePaths: fileSearchScopePaths,
                projectWorkspaceHints: detectedProjectWorkspaces(),
                activeApplicationHints: ActiveApplicationContextPolicy.hints(
                    for: activeApplicationName,
                    allowedToolNames: enabledToolNames
                ),
                recentTurns: await recentConversationContext()
            )
            let startedAt = Date()
            var succeeded = false
            defer {
                recordTelemetry(
                    category: .planning,
                    name: "assistant.plan",
                    startedAt: startedAt,
                    succeeded: succeeded
                )
            }
            let plan = try await assistant.plan(for: request, context: context)
            recordModelSuccess()
            succeeded = true
            await handle(plan)
        } catch {
            handleModelFailure(error)
            speak(error.localizedDescription)
        }
    }

    private func handle(_ plan: AssistantPlan) async {
        if plan.intent == .callTool {
            guard !plan.toolName.isEmpty else {
                speak("I selected a tool, but no tool name was provided.")
                return
            }

            guard enabledToolNames.contains(plan.toolName) else {
                speak("\(plan.toolName) is not enabled.")
                return
            }

            if requiresConfirmationForAllTools
                || toolConfirmationOverrides.contains(plan.toolName)
                || plan.requiresConfirmation
                || mutatingToolNames.contains(plan.toolName) {
                await requestConfirmation(for: plan)
            } else if DefaultToolCatalog.readOnlyToolNames.contains(plan.toolName) {
                await answerWithNativeReadOnlyTools(for: plan)
            } else {
                await execute(plan, confirmed: false, transitionToExecuting: true)
            }
            return
        }

        speak(plan.spokenResponse)
    }

    private func requestConfirmation(for plan: AssistantPlan) async {
        let summary = plan.toolArgumentsSummary.isEmpty ? plan.spokenResponse : plan.toolArgumentsSummary
        pendingPlan = plan
        pendingConfirmation = await confirmationGate.request(summary: summary)
        apply(.confirmationRequired(summary))
        speaker.speak(plan.spokenResponse) { [weak self] in
            self?.startConfirmationVoiceCapture()
        }
    }

    private func answerWithNativeReadOnlyTools(for plan: AssistantPlan) async {
        apply(.executionStarted(plan.toolName))
        let startedAt = Date()
        var succeeded = false
        defer {
            recordTelemetry(
                category: .toolExecution,
                name: "native.\(plan.toolName)",
                startedAt: startedAt,
                succeeded: succeeded
            )
            notifyLongRunningTaskIfNeeded(
                id: "native-\(plan.toolName)-\(startedAt.timeIntervalSince1970)",
                displayName: plan.toolName,
                startedAt: startedAt,
                succeeded: succeeded
            )
        }

        do {
            let request = activeRequest ?? plan.spokenResponse
            let readOnlyNames = DefaultToolCatalog.readOnlyToolNames.intersection(Set(enabledToolNames))
            let activeApplicationName = currentActiveApplicationName()
            let allowedToolNames = Array(readOnlyNames).sorted()
            let context = AssistantContext(
                activeApplicationName: activeApplicationName,
                allowedToolNames: allowedToolNames,
                fileSearchScopePaths: fileSearchScopePaths,
                projectWorkspaceHints: detectedProjectWorkspaces(),
                activeApplicationHints: ActiveApplicationContextPolicy.hints(
                    for: activeApplicationName,
                    allowedToolNames: allowedToolNames
                ),
                recentTurns: await recentConversationContext()
            )
            let response = try await assistant.answerWithReadOnlyTools(for: request, context: context)
            recordModelSuccess()
            recordTranscript(
                response: response,
                toolName: plan.toolName,
                argumentsSummary: "native FoundationModels read-only tools",
                promptVersion: SystemPrompt.readOnlyPromptVersion
            )
            refreshAuditEntries()
            speakToolResult(response)
            succeeded = true
        } catch {
            _ = try? await auditLog.append(
                toolName: plan.toolName,
                argumentsSummary: "native FoundationModels read-only tools",
                resultSummary: "error: \(error.localizedDescription)"
            )
            refreshAuditEntries()
            handleModelFailure(error)
            await execute(plan, confirmed: false, transitionToExecuting: false)
        }
    }

    private func execute(_ plan: AssistantPlan, confirmed: Bool, transitionToExecuting: Bool) async {
        if transitionToExecuting {
            apply(.executionStarted(plan.toolName))
        }
        let startedAt = Date()
        var succeeded = false
        defer {
            recordTelemetry(
                category: .toolExecution,
                name: plan.toolName,
                startedAt: startedAt,
                succeeded: succeeded
            )
            notifyLongRunningTaskIfNeeded(
                id: "tool-\(plan.toolName)-\(startedAt.timeIntervalSince1970)",
                displayName: plan.toolName,
                startedAt: startedAt,
                succeeded: succeeded
            )
        }

        do {
            let invocation = try makeInvocation(from: plan)
            let result = try await toolRegistry.run(invocation, confirmed: confirmed)
            let spokenResponse = await spokenResponse(for: result, plan: plan)
            recordTranscript(response: spokenResponse, toolName: plan.toolName, argumentsSummary: plan.toolArgumentsSummary)
            _ = try? await auditLog.append(
                toolName: plan.toolName,
                argumentsSummary: plan.toolArgumentsSummary,
                resultSummary: spokenResponse
            )
            refreshAuditEntries()
            speakToolResult(spokenResponse)
            succeeded = true
        } catch {
            _ = try? await auditLog.append(
                toolName: plan.toolName,
                argumentsSummary: plan.toolArgumentsSummary,
                resultSummary: "error: \(error.localizedDescription)"
            )
            refreshAuditEntries()
            recordTranscript(
                response: error.localizedDescription,
                toolName: plan.toolName,
                argumentsSummary: plan.toolArgumentsSummary
            )
            apply(.failed(error.localizedDescription))
            speaker.speak(error.localizedDescription) { [weak self] in
                self?.finishSpeaking()
            }
        }
    }

    private func makeInvocation(from plan: AssistantPlan) throws -> ToolInvocation {
        let json = plan.toolArgumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedArguments = Data((json.isEmpty ? "{}" : json).utf8)
        return ToolInvocation(
            toolName: plan.toolName,
            encodedArguments: encodedArguments,
            requiresConfirmation: plan.requiresConfirmation
        )
    }

    private func spokenResponse(for result: ToolResult, plan: AssistantPlan) async -> String {
        let request = activeRequest ?? plan.spokenResponse
        return await ToolOutputSummarizationFallback.spokenResponse(for: result, request: request) { [assistant] result, request in
            try await assistant.summarize(toolResult: result, for: request)
        }
    }

    private func speakToolResult(_ response: String) {
        apply(.executionFinished(response))
        speaker.speak(response) { [weak self] in
            self?.finishSpeaking()
        }
    }

    private func notifyLongRunningTaskIfNeeded(id: String, displayName: String, startedAt: Date, succeeded: Bool) {
        let record = LongRunningTaskRecord(
            id: id,
            displayName: displayName,
            startedAt: startedAt,
            finishedAt: Date(),
            succeeded: succeeded
        )
        guard let notification = taskNotificationPolicy.completionNotification(for: record) else {
            return
        }
        Task {
            await taskNotificationScheduler.deliver(notification)
        }
    }

    private func recordTelemetry(category: LocalTelemetryCategory, name: String, startedAt: Date, succeeded: Bool) {
        let duration = max(0, Date().timeIntervalSince(startedAt))
        let record = LocalTelemetryRecord(
            category: category,
            name: name,
            durationSeconds: duration,
            succeeded: succeeded,
            qualitySignal: succeeded ? "success" : "error",
            modelProfile: foundationModelProfile
        )
        Task {
            try? await telemetryStore.append(record)
        }
    }

    private func clearPendingConfirmation() {
        pendingConfirmation = nil
        pendingPlan = nil
        Task {
            await confirmationGate.clear()
        }
    }

    private func requestMCPClientDecision(
        _ request: PendingMCPClientRequest,
        draft: String,
        elicitationFieldDrafts: [MCPClientElicitationFieldDraft] = []
    ) async -> MCPClientRequestDecision {
        finishMCPClientRequest(.cancel)
        pendingMCPClientRequest = request
        mcpClientDraft = draft
        mcpElicitationFieldDrafts = elicitationFieldDrafts
        statusLine = request.summary
        return await withCheckedContinuation { continuation in
            pendingMCPDecisionContinuation = continuation
        }
    }

    private func finishMCPClientRequest(_ decision: MCPClientRequestDecision) {
        pendingMCPClientRequest = nil
        mcpClientDraft = ""
        mcpElicitationFieldDrafts = []
        guard let continuation = pendingMCPDecisionContinuation else {
            return
        }
        pendingMCPDecisionContinuation = nil
        continuation.resume(returning: decision)
    }

    private func speak(_ response: String) {
        recordTranscript(response: response)
        apply(.responseReady(response))
        speaker.speak(response) { [weak self] in
            self?.finishSpeaking()
        }
    }

    private func recordTranscript(
        response: String,
        toolName: String? = nil,
        argumentsSummary: String? = nil,
        promptVersion: String = SystemPrompt.promptVersion
    ) {
        guard let request = activeRequest, !request.isEmpty else {
            return
        }

        let record = TranscriptRecord(
            request: request,
            response: response,
            toolName: toolName,
            argumentsSummary: argumentsSummary,
            promptVersion: promptVersion,
            modelProfile: foundationModelProfile
        )
        Task {
            _ = try? await transcriptStore.append(record)
        }
    }

    private func replacePermissionSnapshot(_ snapshot: PermissionSnapshot) {
        guard let index = permissionSnapshots.firstIndex(where: { $0.kind == snapshot.kind }) else {
            permissionSnapshots.append(snapshot)
            return
        }

        permissionSnapshots[index] = snapshot
    }

    private var enabledToolNames: [String] {
        enabledToolSummaries.map(\.name)
    }

    private func currentActiveApplicationName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private func recentConversationContext(limit: Int = 3) async -> [AssistantContext.RecentTurn] {
        do {
            return try await transcriptStore.records()
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(limit)
                .reversed()
                .map { record in
                    AssistantContext.RecentTurn(
                        request: Self.promptSnippet(record.request),
                        response: Self.promptSnippet(record.response),
                        toolName: record.toolName
                    )
                }
        } catch {
            return []
        }
    }

    private static func promptSnippet(_ text: String, limit: Int = 500) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else {
            return trimmed
        }
        return String(trimmed.prefix(limit)) + "..."
    }

    private func detectedProjectWorkspaces() -> [ProjectWorkspaceHint] {
        ProjectWorkspaceDetector.detect(in: fileSearchScopePaths)
    }

    private var enabledToolSummaries: [ToolSummary] {
        ToolEnablementPolicy(
            ambientAllowlist: ambientToolAllowlist,
            sessionDisabledToolNames: sessionDisabledToolNames,
            mcpEnabled: isMCPToolEnabled,
            shellEnabled: isShellToolEnabled
        ).enabledSummaries(
            ambientSummaries: Self.ambientToolSummaries,
            mcpSummaries: Self.mcpToolSummaries,
            shellSummary: Self.shellToolSummary
        )
    }

    private var sessionDisabledToolNames: Set<String> {
        isSessionMemoryWriteDisabled ? ["memory.write"] : []
    }

    private func syncToolRegistryAllowlist() {
        let disabledToolNames = ambientToolAllowlist.disabledToolNames.union(sessionDisabledToolNames)
        Task {
            await toolRegistry.resetToolAllowlist()
            for toolName in disabledToolNames {
                await toolRegistry.setToolEnabled(toolName, enabled: false)
            }
        }
    }

    private var mutatingToolNames: Set<String> {
        Set(enabledToolSummaries.filter { $0.mutatesState }.map(\.name))
    }

    private func refreshAssistantToolPrompt() {
        let summaries = enabledToolSummaries
        let nativeToolBase = baseReadOnlyNativeTools
        let shouldLoadMCPNativeTools = isMCPToolEnabled
        let nativeToolLoader = mcpNativeToolLoader
        Task {
            var nativeTools = nativeToolBase
            if shouldLoadMCPNativeTools {
                nativeTools += (try? await nativeToolLoader.load()) ?? []
            }
            await assistant.updateToolConfiguration(
                toolSummaries: summaries,
                readOnlyNativeTools: nativeTools
            )
        }
    }

    private func startMCPHTTPListeners() {
        stopMCPHTTPListeners()
        mcpListenerStatusLine = "MCP listener starting."
        mcpListenerSetupTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let configurations = MCPHTTPListenerPolicy.listenerConfigurations(
                    from: try await mcpServerRegistry.configurations()
                )
                for configuration in configurations {
                    mcpServerHealthStates[configuration.name] = .listening
                    mcpServerHealthDetails[configuration.name] = "starting listener"
                }
                refreshMCPServerHealthStatus()
                guard !configurations.isEmpty else {
                    mcpListenerStatusLine = "No Streamable HTTP MCP servers configured."
                    return
                }

                mcpListenerTasks = configurations.map { configuration in
                    Task { @MainActor [weak self] in
                        await self?.runMCPHTTPListener(configuration: configuration)
                    }
                }
                mcpListenerStatusLine = configurations.count == 1
                    ? "Listening to 1 MCP HTTP server."
                    : "Listening to \(configurations.count) MCP HTTP servers."
                for configuration in configurations {
                    mcpServerHealthStates[configuration.name] = .listening
                    mcpServerHealthDetails[configuration.name] = "listening for background requests"
                }
                refreshMCPServerHealthStatus()
            } catch {
                mcpListenerStatusLine = error.localizedDescription
                refreshMCPServerHealthStatus()
            }
        }
    }

    private func stopMCPHTTPListeners() {
        mcpListenerSetupTask?.cancel()
        mcpListenerSetupTask = nil
        mcpListenerTasks.forEach { $0.cancel() }
        mcpListenerTasks = []
        mcpListenerLastEventIDs = [:]
        mcpServerHealthStates = [:]
        mcpServerHealthDetails = [:]
        mcpListenerStatusLine = "MCP listener off"
        refreshMCPServerHealthStatus()
        finishMCPClientRequest(.cancel)
    }

    private func runMCPHTTPListener(configuration: MCPServerConfiguration) async {
        while isMCPToolEnabled, !Task.isCancelled {
            do {
                let result = try await MCPStreamableHTTPClient(
                    configuration: configuration,
                    clientRequestHandlers: mcpClientRequestBroker.handlers
                ).listenForServerRequests(lastEventID: mcpListenerLastEventIDs[configuration.name])
                guard result.endpointAvailable else {
                    mcpListenerStatusLine = "\(configuration.name) does not expose MCP HTTP GET SSE."
                    mcpServerHealthStates[configuration.name] = .unsupported
                    mcpServerHealthDetails[configuration.name] = "GET SSE unavailable"
                    refreshMCPServerHealthStatus()
                    return
                }

                if let lastEventID = result.lastEventID {
                    mcpListenerLastEventIDs[configuration.name] = lastEventID
                }
                if result.handledMessages > 0 {
                    mcpListenerStatusLine = "\(configuration.name) handled \(result.handledMessages) background MCP request(s)."
                    mcpServerHealthStates[configuration.name] = .handled
                    mcpServerHealthDetails[configuration.name] = "handled \(result.handledMessages) background request(s)"
                    refreshMCPServerHealthStatus()
                }
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch is CancellationError {
                return
            } catch {
                mcpListenerStatusLine = "\(configuration.name) MCP listener error: \(error.localizedDescription)"
                mcpServerHealthStates[configuration.name] = .error
                mcpServerHealthDetails[configuration.name] = error.localizedDescription
                refreshMCPServerHealthStatus()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func refreshMCPServerHealthStatus() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                mcpServerHealthLines = MCPServerHealthReporter.lines(
                    configurations: try await mcpServerRegistry.allConfigurations(),
                    enabled: isMCPToolEnabled,
                    states: mcpServerHealthStates,
                    details: mcpServerHealthDetails
                )
            } catch {
                mcpServerHealthLines = [
                    MCPServerHealthLine(name: "mcp config", transport: .stdio, state: .error, detail: error.localizedDescription)
                ]
            }
        }
    }

    private static func defaultElicitationDraft(for request: MCPElicitationRequest) -> String {
        guard let data = request.schemaJSON.data(using: .utf8),
              let schema = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let properties = schema["properties"] as? [String: [String: Any]] else {
            return "{}"
        }

        let required = schema["required"] as? [String] ?? []
        var content: [String: Any] = [:]
        for key in required {
            guard let property = properties[key] else {
                continue
            }
            if let defaultValue = property["default"] {
                content[key] = defaultValue
                continue
            }
            switch property["type"] as? String {
            case "boolean":
                content[key] = false
            case "number", "integer":
                content[key] = 0
            default:
                content[key] = ""
            }
        }

        guard JSONSerialization.isValidJSONObject(content),
              let encoded = try? JSONSerialization.data(withJSONObject: content, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: encoded, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func defaultElicitationFieldDrafts(for request: MCPElicitationRequest) -> [MCPClientElicitationFieldDraft] {
        request.fields.map { field in
            let value = field.defaultValue ?? {
                if let firstEnumValue = field.enumValues.first {
                    return firstEnumValue
                }
                switch field.type {
                case .boolean:
                    return "false"
                default:
                    return ""
                }
            }()
            return MCPClientElicitationFieldDraft(field: field, value: value)
        }
    }

    private static func elicitationContentJSON(from drafts: [MCPClientElicitationFieldDraft]) throws -> String {
        var content: [String: Any] = [:]
        for draft in drafts {
            let trimmed = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty, !draft.field.required, draft.field.type != .boolean {
                continue
            }

            switch draft.field.type {
            case .string:
                content[draft.field.name] = trimmed
            case .boolean:
                content[draft.field.name] = trimmed == "true"
            case .integer:
                guard let value = Int(trimmed) else {
                    throw ToolExecutionError.invalidArguments("MCP elicitation field must be an integer: \(draft.field.name)")
                }
                content[draft.field.name] = value
            case .number:
                guard let value = Double(trimmed) else {
                    throw ToolExecutionError.invalidArguments("MCP elicitation field must be a number: \(draft.field.name)")
                }
                content[draft.field.name] = value
            }
        }

        let encoded = try JSONSerialization.data(withJSONObject: content, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: encoded, as: UTF8.self)
    }

    private func refreshConfiguredAdapter() {
        Task {
            do {
                adapterFailureCircuitBreaker.reset()
                guard usesConfiguredAdapter else {
                    await assistant.updateModel(.default)
                    foundationModelAdapterStatusLine = "Adapter disabled"
                    foundationModelProfile = "default"
                    return
                }

                guard let configuredModel = try await adapterLoader.configuredModelAndProfileIfPresent() else {
                    foundationModelAdapterStatusLine = "Adapter config not found"
                    foundationModelProfile = "default"
                    return
                }
                guard FoundationModelPrivacyLock.allows(
                    profile: configuredModel.profile,
                    requiresLocalOnly: requiresLocalFoundationModels
                ) else {
                    await assistant.updateModel(.default)
                    foundationModelProfile = "default"
                    foundationModelAdapterStatusLine = "Adapter blocked by local-only lock"
                    statusLine = "Blocked non-local FoundationModels profile."
                    return
                }

                await assistant.updateModel(configuredModel.model)
                foundationModelProfile = configuredModel.profile
                foundationModelAdapterStatusLine = "Adapter loaded"
                statusLine = "FoundationModels adapter loaded."
            } catch {
                foundationModelAdapterStatusLine = "Adapter error: \(error.localizedDescription)"
                foundationModelProfile = "default"
                statusLine = error.localizedDescription
            }
        }
    }

    private func recordModelSuccess() {
        adapterFailureCircuitBreaker.recordSuccess()
    }

    private func handleModelFailure(_ error: any Error) {
        guard adapterFailureCircuitBreaker.recordFailure(modelProfile: foundationModelProfile) else {
            return
        }

        usesConfiguredAdapter = false
        foundationModelAdapterStatusLine = "Adapter disabled after repeated errors"
        statusLine = "Disabled FoundationModels adapter after repeated errors: \(error.localizedDescription)"
    }

    private func answerAuditQuestionIfNeeded(_ request: String) async -> Bool {
        let normalized = request
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard normalized.contains("what did cerberus just do")
                || normalized.contains("what did you just do")
                || normalized.contains("last tool call")
                || normalized.contains("recent tool calls") else {
            return false
        }

        speak(await lastToolActionSummary())
        return true
    }

    private func lastToolActionSummary() async -> String {
        do {
            let entries = try await auditLog.recentEntries(limit: 5)
            recentAuditEntries = entries

            return AuditLogActionSummary.lastToolActionSummary(from: entries)
        } catch {
            return error.localizedDescription
        }
    }
}
