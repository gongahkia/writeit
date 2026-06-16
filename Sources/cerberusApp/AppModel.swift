import Foundation
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

struct MCPClientElicitationFieldDraft: Identifiable {
    let field: MCPElicitationField
    var value: String

    var id: String {
        field.id
    }
}

private enum MCPClientRequestDecision: Sendable {
    case approve(String)
    case decline
    case cancel
}

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
    @Published private(set) var pendingConfirmation: PendingConfirmation?
    @Published private(set) var isConfirmationVoiceActive = false
    @Published private(set) var isWakeWordMonitoring = false
    @Published private(set) var audioOutputRouteLine = "Output route unknown"
    @Published private(set) var isAudioOutputLikelyAirPods = false
    @Published private(set) var recentAuditEntries: [AuditLogEntry] = []
    @Published private(set) var transcriptRecords: [TranscriptRecord] = []
    @Published private(set) var pendingMCPClientRequest: PendingMCPClientRequest?
    @Published private(set) var mcpListenerStatusLine = "MCP listener off"
    @Published var isAutoSilenceEnabled = true
    @Published var isVoiceConfirmationEnabled = true
    @Published var wakePhrase = UserDefaults.standard.string(forKey: CerberusAppModel.wakePhraseDefaultsKey) ?? "hey cerberus" {
        didSet {
            UserDefaults.standard.set(wakePhrase, forKey: Self.wakePhraseDefaultsKey)
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
    @Published var transcriptDraft = ""
    @Published var mcpClientDraft = ""
    @Published var mcpElicitationFieldDrafts: [MCPClientElicitationFieldDraft] = []

    private let permissionCenter = PermissionCenter()
    private let transcriber = Transcriber()
    private let wakeWordTranscriber = Transcriber()
    private let speaker = Speaker()
    private let earconPlayer = EarconPlayer()
    private let hotKeyMonitor = GlobalHotKeyMonitor()
    private let headGestureDetector = HeadGestureDetector()
    private let mediaKeyInterceptor = MediaKeyInterceptor()
    private let toolRegistry: ToolRegistry
    private let confirmationGate = ConfirmationGate()
    private let auditLog = AuditLog()
    private let assistant: Assistant
    private let transcriptStore = EncryptedTranscriptStore()
    private let adapterLoader = FoundationModelAdapterLoader()
    private let mcpServerRegistry = MCPServerRegistry()
    private let mcpClientRequestBroker: MCPClientRequestBroker
    private var pendingPlan: AssistantPlan?
    private var activeRequest: String?
    private var pendingMCPDecisionContinuation: CheckedContinuation<MCPClientRequestDecision, Never>?
    private var mcpListenerSetupTask: Task<Void, Never>?
    private var mcpListenerTasks: [Task<Void, Never>] = []
    private var mcpListenerLastEventIDs: [String: String] = [:]
    private var silenceTask: Task<Void, Never>?
    private var confirmationVoiceTimeoutTask: Task<Void, Never>?
    private let silenceTimeoutNanoseconds: UInt64 = 1_500_000_000
    private let confirmationVoiceTimeoutNanoseconds: UInt64 = 8_000_000_000
    private static let ambientToolSummaries = DefaultToolCatalog.summaries
    private static let mcpToolSummaries = makeMCPTools(clientRequestHandlers: .none).map(\.summary)
    private static let shellToolSummary = ShellTool().summary
    private static let wakePhraseDefaultsKey = "wakePhrase"

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

    init() {
        let mcpClientRequestBroker = MCPClientRequestBroker()
        let shellTool = ShellTool(allowExecution: true, executor: ShellXPCCommandExecutor())
        let mcpTools = Self.makeMCPTools(clientRequestHandlers: mcpClientRequestBroker.handlers)
        let tools = DefaultToolCatalog.tools + mcpTools + [AnyAssistantTool(shellTool)]
        self.mcpClientRequestBroker = mcpClientRequestBroker
        toolRegistry = (try? ToolRegistry(tools: tools)) ?? ToolRegistry()
        assistant = Assistant(
            toolSummaries: Self.ambientToolSummaries,
            readOnlyNativeTools: DefaultToolCatalog.readOnlyFoundationModelTools(auditLog: auditLog)
        )
        mcpClientRequestBroker.model = self
        refreshPermissions()
        refreshAudioOutputRoute()
        refreshAuditEntries()
        startTriggers()
        loadConfiguredAdapterIfPresent()
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

    var grantedPermissionCount: Int {
        permissionSnapshots.filter { $0.state == .granted }.count
    }

    var enabledToolDisplayText: String {
        var labels = ["Apps", "Calendar", "Files", "Mail", "Memory", "Music", "Reminders", "Screen", "Web"]
        if isMCPToolEnabled {
            labels.append("MCP")
        }
        if isShellToolEnabled {
            labels.append("Shell")
        }
        return labels.sorted().joined(separator: ", ")
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
        startWakeWordMonitoringIfNeeded()
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

    func refreshAuditEntries() {
        Task {
            do {
                recentAuditEntries = try await auditLog.recentEntries(limit: 5)
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

    func calibrateHeadGestures() {
        statusLine = headGestureDetector.calibrate()
            ? "Head gesture neutral pose calibrated."
            : "No AirPods motion sample is available yet."
    }

    func resetHeadGestureThresholds() {
        headNodThreshold = 0.35
        headShakeThreshold = 0.45
        updateHeadGestureThresholds()
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
        recentEvents.insert("\(transition.from.rawValue) -> \(transition.to.rawValue)", at: 0)
        recentEvents = Array(recentEvents.prefix(5))
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
        headGestureDetector.updateThresholds(pitch: headNodThreshold, yaw: headShakeThreshold)
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
              !wakeWordTranscriber.isRunning else {
            return
        }

        isWakeWordMonitoring = true
        Task {
            do {
                try await wakeWordTranscriber.start { [weak self] update in
                    self?.handleWakeWordUpdate(update)
                }
            } catch {
                isWakeWordMonitoring = false
                statusLine = error.localizedDescription
            }
        }
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

    private func stopWakeWordMonitoring() {
        guard isWakeWordMonitoring || wakeWordTranscriber.isRunning else {
            return
        }

        isWakeWordMonitoring = false
        Task {
            await wakeWordTranscriber.cancel()
        }
    }

    private func stopWakeWordMonitoringAndWait() async {
        guard isWakeWordMonitoring || wakeWordTranscriber.isRunning else {
            return
        }

        isWakeWordMonitoring = false
        await wakeWordTranscriber.cancel()
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
        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled else {
                return
            }
            self?.finishListeningAndProcess()
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
        confirmationVoiceTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled else {
                return
            }
            self?.stopConfirmationVoiceCapture()
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
            let context = AssistantContext(allowedToolNames: enabledToolNames)
            let plan = try await assistant.plan(for: request, context: context)
            await handle(plan)
        } catch {
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

            if plan.requiresConfirmation || mutatingToolNames.contains(plan.toolName) {
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

        do {
            let request = activeRequest ?? plan.spokenResponse
            let readOnlyNames = DefaultToolCatalog.readOnlyToolNames.intersection(Set(enabledToolNames))
            let context = AssistantContext(allowedToolNames: Array(readOnlyNames).sorted())
            let response = try await assistant.answerWithReadOnlyTools(for: request, context: context)
            recordTranscript(
                response: response,
                toolName: plan.toolName,
                argumentsSummary: "native FoundationModels read-only tools"
            )
            refreshAuditEntries()
            speakToolResult(response)
        } catch {
            _ = try? await auditLog.append(
                toolName: plan.toolName,
                argumentsSummary: "native FoundationModels read-only tools",
                resultSummary: "error: \(error.localizedDescription)"
            )
            refreshAuditEntries()
            await execute(plan, confirmed: false, transitionToExecuting: false)
        }
    }

    private func execute(_ plan: AssistantPlan, confirmed: Bool, transitionToExecuting: Bool) async {
        if transitionToExecuting {
            apply(.executionStarted(plan.toolName))
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
        let fallback = result.spokenSummary
        let request = activeRequest ?? plan.spokenResponse

        do {
            return try await assistant.summarize(toolResult: result, for: request)
        } catch {
            return fallback
        }
    }

    private func speakToolResult(_ response: String) {
        apply(.executionFinished(response))
        speaker.speak(response) { [weak self] in
            self?.finishSpeaking()
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

    private func recordTranscript(response: String, toolName: String? = nil, argumentsSummary: String? = nil) {
        guard let request = activeRequest, !request.isEmpty else {
            return
        }

        let record = TranscriptRecord(
            request: request,
            response: response,
            toolName: toolName,
            argumentsSummary: argumentsSummary
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

    private var enabledToolSummaries: [ToolSummary] {
        var summaries = Self.ambientToolSummaries
        if isMCPToolEnabled {
            summaries += Self.mcpToolSummaries
        }
        if isShellToolEnabled {
            summaries.append(Self.shellToolSummary)
        }
        return summaries.sorted { $0.name < $1.name }
    }

    private var mutatingToolNames: Set<String> {
        Set(enabledToolSummaries.filter { $0.mutatesState }.map(\.name))
    }

    private func refreshAssistantToolPrompt() {
        let summaries = enabledToolSummaries
        Task {
            await assistant.updateTools(summaries)
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
                let configurations = try await mcpServerRegistry.configurations()
                    .filter { $0.transport == .streamableHTTP }
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
            } catch {
                mcpListenerStatusLine = error.localizedDescription
            }
        }
    }

    private func stopMCPHTTPListeners() {
        mcpListenerSetupTask?.cancel()
        mcpListenerSetupTask = nil
        mcpListenerTasks.forEach { $0.cancel() }
        mcpListenerTasks = []
        mcpListenerLastEventIDs = [:]
        mcpListenerStatusLine = "MCP listener off"
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
                    return
                }

                if let lastEventID = result.lastEventID {
                    mcpListenerLastEventIDs[configuration.name] = lastEventID
                }
                if result.handledMessages > 0 {
                    mcpListenerStatusLine = "\(configuration.name) handled \(result.handledMessages) background MCP request(s)."
                }
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch is CancellationError {
                return
            } catch {
                mcpListenerStatusLine = "\(configuration.name) MCP listener error: \(error.localizedDescription)"
                try? await Task.sleep(nanoseconds: 5_000_000_000)
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

    private func loadConfiguredAdapterIfPresent() {
        Task {
            do {
                guard let model = try await adapterLoader.configuredModelIfPresent() else {
                    return
                }

                await assistant.updateModel(model)
                statusLine = "FoundationModels adapter loaded."
            } catch {
                statusLine = error.localizedDescription
            }
        }
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

            guard let latest = entries.first else {
                return "No tool calls recorded yet."
            }

            return "Last tool call: \(latest.toolName). Result: \(latest.resultSummary)"
        } catch {
            return error.localizedDescription
        }
    }
}
