import Foundation
import cerberusCore

@MainActor
final class CerberusAppModel: ObservableObject {
    @Published private(set) var stateMachine = AssistantStateMachine()
    @Published private(set) var statusLine = "Ready"
    @Published private(set) var recentEvents: [String] = []
    @Published private(set) var permissionSnapshots: [PermissionSnapshot] = []
    @Published private(set) var pendingConfirmation: PendingConfirmation?
    @Published var transcriptDraft = ""

    private let permissionCenter = PermissionCenter()
    private let transcriber = Transcriber()
    private let speaker = Speaker()
    private let earconPlayer = EarconPlayer()
    private let hotKeyMonitor = GlobalHotKeyMonitor()
    private let headGestureDetector = HeadGestureDetector()
    private let mediaKeyInterceptor = MediaKeyInterceptor()
    private let toolRegistry: ToolRegistry
    private let assistant = Assistant(toolSummaries: DefaultToolCatalog.summaries)
    private let confirmationGate = ConfirmationGate()
    private let auditLog = AuditLog()
    private var pendingPlan: AssistantPlan?
    private var activeRequest: String?
    private var silenceTask: Task<Void, Never>?
    private let silenceTimeoutNanoseconds: UInt64 = 1_500_000_000

    init() {
        toolRegistry = (try? ToolRegistry(tools: DefaultToolCatalog.tools)) ?? ToolRegistry()
        refreshPermissions()
        startTriggers()
    }

    var state: AssistantState {
        stateMachine.state
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
        if apply(.wakeDetected(trigger)) {
            startVoiceCapture()
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
    }

    func cancel() {
        transcriptDraft = ""
        activeRequest = nil
        silenceTask?.cancel()
        silenceTask = nil
        Task {
            await transcriber.cancel()
        }
        speaker.stop()
        clearPendingConfirmation()
        apply(.cancelRequested)
    }

    func reset() {
        transcriptDraft = ""
        activeRequest = nil
        silenceTask?.cancel()
        silenceTask = nil
        Task {
            await transcriber.cancel()
        }
        speaker.stop()
        clearPendingConfirmation()
        apply(.reset)
    }

    func refreshPermissions() {
        permissionSnapshots = permissionCenter.currentSnapshots()
    }

    func requestPermission(_ kind: SystemPermission) {
        Task {
            let snapshot = await permissionCenter.request(kind)
            replacePermissionSnapshot(snapshot)
        }
    }

    func approvePendingConfirmation() {
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
                if state == .listening || state == .speaking {
                    cancel()
                }
            case .triplePress:
                startListening(trigger: .stemTriplePress)
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

    private func scheduleSilenceTimeoutIfNeeded() {
        silenceTask?.cancel()

        guard state == .listening,
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

    private func runReasoning(for request: String) async {
        do {
            activeRequest = request
            let plan = try await assistant.plan(for: request)
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

            if plan.requiresConfirmation {
                await requestConfirmation(for: plan)
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
        speaker.speak(plan.spokenResponse)
    }

    private func execute(_ plan: AssistantPlan, confirmed: Bool, transitionToExecuting: Bool) async {
        if transitionToExecuting {
            apply(.executionStarted(plan.toolName))
        }

        do {
            let invocation = try makeInvocation(from: plan)
            let result = try await toolRegistry.run(invocation, confirmed: confirmed)
            let spokenResponse = await spokenResponse(for: result, plan: plan)
            _ = try? await auditLog.append(
                toolName: plan.toolName,
                argumentsSummary: plan.toolArgumentsSummary,
                resultSummary: spokenResponse
            )
            speakToolResult(spokenResponse)
        } catch {
            _ = try? await auditLog.append(
                toolName: plan.toolName,
                argumentsSummary: plan.toolArgumentsSummary,
                resultSummary: "error: \(error.localizedDescription)"
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

    private func speak(_ response: String) {
        apply(.responseReady(response))
        speaker.speak(response) { [weak self] in
            self?.finishSpeaking()
        }
    }

    private func replacePermissionSnapshot(_ snapshot: PermissionSnapshot) {
        guard let index = permissionSnapshots.firstIndex(where: { $0.kind == snapshot.kind }) else {
            permissionSnapshots.append(snapshot)
            return
        }

        permissionSnapshots[index] = snapshot
    }
}
