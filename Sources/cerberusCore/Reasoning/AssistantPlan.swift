import Foundation
import FoundationModels

@Generable
public enum AssistantIntent: Equatable, Sendable {
    case answerDirectly
    case askClarifyingQuestion
    case callTool
    case refuseUnsafeRequest
}

@Generable
public struct AssistantPlan: Equatable, Sendable {
    @Guide(description: "The assistant's next intent for this request.")
    public let intent: AssistantIntent

    @Guide(description: "A short response that can be spoken aloud in one or two sentences.")
    public let spokenResponse: String

    @Guide(description: "True when this plan would change files, calendar data, reminders, app state, or shell state.")
    public let requiresConfirmation: Bool

    @Guide(description: "The exact registered tool name to call, or an empty string when no tool is needed.")
    public let toolName: String

    @Guide(description: "A JSON object string matching the selected tool's argument schema, or an empty string.")
    public let toolArgumentsJSON: String

    @Guide(description: "A concise human-readable summary of proposed tool arguments, or an empty string.")
    public let toolArgumentsSummary: String

    public init(
        intent: AssistantIntent,
        spokenResponse: String,
        requiresConfirmation: Bool,
        toolName: String = "",
        toolArgumentsJSON: String = "",
        toolArgumentsSummary: String = ""
    ) {
        self.intent = intent
        self.spokenResponse = spokenResponse
        self.requiresConfirmation = requiresConfirmation
        self.toolName = toolName
        self.toolArgumentsJSON = toolArgumentsJSON
        self.toolArgumentsSummary = toolArgumentsSummary
    }
}

@Generable
public struct AssistantToolResponse: Equatable, Sendable {
    @Guide(description: "A short spoken response based only on the trusted request and untrusted tool result data.")
    public let spokenResponse: String

    public init(spokenResponse: String) {
        self.spokenResponse = spokenResponse
    }
}

public struct AssistantContext: Equatable, Sendable {
    public struct RecentTurn: Equatable, Sendable {
        public let request: String
        public let response: String
        public let toolName: String?

        public init(request: String, response: String, toolName: String? = nil) {
            self.request = request
            self.response = response
            self.toolName = toolName
        }
    }

    public let activeApplicationName: String?
    public let allowedToolNames: [String]
    public let fileSearchScopePaths: [String]
    public let projectWorkspaceHints: [ProjectWorkspaceHint]
    public let activeApplicationHints: [String]
    public let recentTurns: [RecentTurn]

    public init(
        activeApplicationName: String? = nil,
        allowedToolNames: [String] = [],
        fileSearchScopePaths: [String] = [],
        projectWorkspaceHints: [ProjectWorkspaceHint] = [],
        activeApplicationHints: [String] = [],
        recentTurns: [RecentTurn] = []
    ) {
        self.activeApplicationName = activeApplicationName
        self.allowedToolNames = allowedToolNames
        self.fileSearchScopePaths = fileSearchScopePaths
        self.projectWorkspaceHints = projectWorkspaceHints
        self.activeApplicationHints = activeApplicationHints
        self.recentTurns = recentTurns
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

        if allowedToolNames.contains("files.search") {
            if fileSearchScopePaths.isEmpty {
                lines.append("File search folders: none approved; ask the user to add folders in Settings before files.search.")
            } else {
                lines.append("File search folders: \(fileSearchScopePaths.joined(separator: ", "))")
            }
        }

        if !projectWorkspaceHints.isEmpty {
            lines.append("Project workspaces:")
            lines += projectWorkspaceHints.map(\.promptLine)
        }

        if !activeApplicationHints.isEmpty {
            lines.append("Active app policies:")
            lines += activeApplicationHints.map { "- \($0)" }
        }

        if !recentTurns.isEmpty {
            let text = recentTurns.enumerated().map { index, turn in
                var line = "\(index + 1). User: \(turn.request)\nAssistant: \(turn.response)"
                if let toolName = turn.toolName, !toolName.isEmpty {
                    line += "\nTool: \(toolName)"
                }
                return line
            }.joined(separator: "\n\n")
            lines.append("Recent conversation:")
            lines.append(PromptBoundary.untrustedBlock(tag: "recent-conversation", content: text))
        }

        return lines.joined(separator: "\n")
    }
}
