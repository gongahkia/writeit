import Foundation
import cerberusCore

@MainActor
final class CerberusAppModel: ObservableObject {
    @Published private(set) var stateMachine = AssistantStateMachine()
    @Published private(set) var statusLine = "Ready"
    @Published private(set) var recentEvents: [String] = []
    @Published var transcriptDraft = ""

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
    }

    func finishListeningWithDraft() {
        guard !transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            apply(.cancelRequested)
            return
        }
        apply(.silenceDetected)
    }

    func simulateResponse() {
        let text = transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = text.isEmpty ? "I did not hear a request." : "Heard: \(text)"
        apply(.responseReady(response))
    }

    func finishSpeaking() {
        transcriptDraft = ""
        apply(.speechFinished)
    }

    func cancel() {
        transcriptDraft = ""
        apply(.cancelRequested)
    }

    func reset() {
        transcriptDraft = ""
        apply(.reset)
    }

    private func apply(_ event: AssistantEvent) {
        guard let transition = stateMachine.handle(event) else {
            return
        }

        statusLine = transition.message ?? transition.to.displayName
        recentEvents.insert("\(transition.from.rawValue) -> \(transition.to.rawValue)", at: 0)
        recentEvents = Array(recentEvents.prefix(5))
    }
}
