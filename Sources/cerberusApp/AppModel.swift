import Foundation
import cerberusCore

@MainActor
final class CerberusAppModel: ObservableObject {
    @Published private(set) var stateMachine = AssistantStateMachine()
    @Published private(set) var statusLine = "Ready"
    @Published private(set) var recentEvents: [String] = []
    @Published private(set) var permissionSnapshots: [PermissionSnapshot] = []
    @Published var transcriptDraft = ""

    private let permissionCenter = PermissionCenter()
    private let transcriber = Transcriber()
    private let speaker = Speaker()

    init() {
        refreshPermissions()
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
        apply(.wakeDetected(trigger))
        startVoiceCapture()
    }

    func finishListeningAndProcess() {
        Task {
            await transcriber.stop()
            finishListeningWithDraft()
            simulateResponse()
        }
    }

    private func finishListeningWithDraft() {
        guard !transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            apply(.cancelRequested)
            return
        }
        apply(.silenceDetected)
    }

    private func simulateResponse() {
        let text = transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = text.isEmpty ? "I did not hear a request." : "Heard: \(text)"
        apply(.responseReady(response))
        speaker.speak(response) { [weak self] in
            self?.finishSpeaking()
        }
    }

    func finishSpeaking() {
        transcriptDraft = ""
        apply(.speechFinished)
    }

    func cancel() {
        transcriptDraft = ""
        transcriber.cancel()
        speaker.stop()
        apply(.cancelRequested)
    }

    func reset() {
        transcriptDraft = ""
        transcriber.cancel()
        speaker.stop()
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

    private func apply(_ event: AssistantEvent) {
        guard let transition = stateMachine.handle(event) else {
            return
        }

        statusLine = transition.message ?? transition.to.displayName
        recentEvents.insert("\(transition.from.rawValue) -> \(transition.to.rawValue)", at: 0)
        recentEvents = Array(recentEvents.prefix(5))
    }

    private func startVoiceCapture() {
        Task {
            do {
                try await transcriber.start { [weak self] update in
                    self?.transcriptDraft = update.text
                }
            } catch {
                apply(.failed(error.localizedDescription))
                speaker.speak(error.localizedDescription) { [weak self] in
                    self?.finishSpeaking()
                }
            }
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
