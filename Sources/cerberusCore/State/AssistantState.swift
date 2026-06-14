import Foundation

public enum AssistantState: String, CaseIterable, Equatable, Sendable {
    case idle
    case listening
    case reasoning
    case awaitingConfirm = "awaiting_confirm"
    case executing
    case speaking

    public var isMicrophoneActive: Bool {
        self == .listening
    }

    public var displayName: String {
        switch self {
        case .idle:
            "Idle"
        case .listening:
            "Listening"
        case .reasoning:
            "Reasoning"
        case .awaitingConfirm:
            "Awaiting confirm"
        case .executing:
            "Executing"
        case .speaking:
            "Speaking"
        }
    }
}

public enum AssistantEvent: Equatable, Sendable {
    case wakeDetected(WakeTrigger)
    case silenceDetected
    case cancelRequested
    case confirmationRequired(String)
    case responseReady(String)
    case executionStarted(String)
    case confirmationAccepted
    case confirmationDenied
    case executionFinished(String)
    case speechFinished
    case failed(String)
    case reset
}

public enum WakeTrigger: String, CaseIterable, Equatable, Sendable {
    case manual
    case hotKey = "hot_key"
    case headNod = "head_nod"
    case stemTriplePress = "stem_triple_press"
}

public struct AssistantTransition: Equatable, Sendable {
    public let from: AssistantState
    public let event: AssistantEvent
    public let to: AssistantState
    public let message: String?

    public init(from: AssistantState, event: AssistantEvent, to: AssistantState, message: String? = nil) {
        self.from = from
        self.event = event
        self.to = to
        self.message = message
    }
}

public struct AssistantStateMachine: Sendable {
    public private(set) var state: AssistantState

    public init(initialState: AssistantState = .idle) {
        state = initialState
    }

    @discardableResult
    public mutating func handle(_ event: AssistantEvent) -> AssistantTransition? {
        guard let nextState = Self.nextState(from: state, event: event) else {
            return nil
        }

        let transition = AssistantTransition(
            from: state,
            event: event,
            to: nextState,
            message: Self.message(for: event)
        )
        state = nextState
        return transition
    }

    public static func nextState(from state: AssistantState, event: AssistantEvent) -> AssistantState? {
        switch (state, event) {
        case (.idle, .wakeDetected):
            .listening
        case (.listening, .silenceDetected):
            .reasoning
        case (.listening, .cancelRequested):
            .idle
        case (.reasoning, .cancelRequested):
            .idle
        case (.reasoning, .confirmationRequired):
            .awaitingConfirm
        case (.reasoning, .executionStarted):
            .executing
        case (.reasoning, .responseReady):
            .speaking
        case (.awaitingConfirm, .confirmationAccepted):
            .executing
        case (.awaitingConfirm, .confirmationDenied):
            .idle
        case (.awaitingConfirm, .cancelRequested):
            .idle
        case (.executing, .executionFinished):
            .speaking
        case (.speaking, .speechFinished):
            .idle
        case (.speaking, .cancelRequested):
            .idle
        case (_, .failed):
            .speaking
        case (_, .reset):
            .idle
        default:
            nil
        }
    }

    private static func message(for event: AssistantEvent) -> String? {
        switch event {
        case .wakeDetected(let trigger):
            "Wake trigger: \(trigger.rawValue)"
        case .confirmationRequired(let summary):
            summary
        case .responseReady(let response):
            response
        case .executionStarted(let toolName):
            "Executing \(toolName)"
        case .executionFinished(let summary):
            summary
        case .failed(let reason):
            reason
        default:
            nil
        }
    }
}
