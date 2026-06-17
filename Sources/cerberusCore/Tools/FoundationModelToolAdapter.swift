import Foundation
import FoundationModels

public struct FoundationModelToolAdapter<ToolImplementation: AssistantTool>: FoundationModels.Tool where ToolImplementation.Arguments: Generable {
    public typealias Arguments = ToolImplementation.Arguments
    public typealias Output = String

    private let tool: ToolImplementation
    private let auditLog: AuditLog?

    public init(_ tool: ToolImplementation, auditLog: AuditLog? = nil) {
        self.tool = tool
        self.auditLog = auditLog
    }

    public var name: String {
        tool.name
    }

    public var description: String {
        tool.capability
    }

    public var includesSchemaInInstructions: Bool {
        true
    }

    public func call(arguments: Arguments) async throws -> String {
        guard !tool.mutatesState else {
            throw ToolExecutionError.confirmationRequired(tool.name)
        }

        try tool.validate(arguments)
        let result = try await tool.run(arguments: arguments)
        let output = result.promptPayload

        if let auditLog {
            _ = try? await auditLog.append(
                toolName: tool.name,
                argumentsSummary: String(describing: arguments),
                resultSummary: result.spokenSummary
            )
        }

        return output
    }
}

private extension ToolResult {
    var promptPayload: String {
        let payload = untrustedPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else {
            return spokenSummary
        }

        let summary = PromptBoundary.escapeClosingTags(in: spokenSummary, tag: "tool-output")
        return """
        Summary: \(summary)
        Untrusted tool output:
        \(PromptBoundary.untrustedBlock(content: payload))
        """
    }
}
