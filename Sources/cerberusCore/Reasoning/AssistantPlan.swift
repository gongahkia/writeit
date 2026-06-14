import Foundation
import FoundationModels

@Generable
public enum AssistantIntent {
    case answerDirectly
    case askClarifyingQuestion
    case callTool
    case refuseUnsafeRequest
}

@Generable
public struct AssistantPlan {
    @Guide(description: "The assistant's next intent for this request.")
    public let intent: AssistantIntent

    @Guide(description: "A short response that can be spoken aloud in one or two sentences.")
    public let spokenResponse: String

    @Guide(description: "True when this plan would change files, calendar data, reminders, app state, or shell state.")
    public let requiresConfirmation: Bool

    @Guide(description: "The exact registered tool name to call, or an empty string when no tool is needed.")
    public let toolName: String

    @Guide(description: "A concise human-readable summary of proposed tool arguments, or an empty string.")
    public let toolArgumentsSummary: String

    public init(
        intent: AssistantIntent,
        spokenResponse: String,
        requiresConfirmation: Bool,
        toolName: String = "",
        toolArgumentsSummary: String = ""
    ) {
        self.intent = intent
        self.spokenResponse = spokenResponse
        self.requiresConfirmation = requiresConfirmation
        self.toolName = toolName
        self.toolArgumentsSummary = toolArgumentsSummary
    }
}

public struct AssistantContext: Equatable, Sendable {
    public let activeApplicationName: String?
    public let allowedToolNames: [String]

    public init(activeApplicationName: String? = nil, allowedToolNames: [String] = []) {
        self.activeApplicationName = activeApplicationName
        self.allowedToolNames = allowedToolNames
    }

    public var promptFragment: String {
        var lines: [String] = []

        if let activeApplicationName {
            lines.append("Active app: \(activeApplicationName)")
        }

        if allowedToolNames.isEmpty {
            lines.append("Allowed tools: none")
        } else {
            lines.append("Allowed tools: \(allowedToolNames.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }
}
