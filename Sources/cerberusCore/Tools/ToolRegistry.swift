import Foundation

public actor ToolRegistry {
    private var tools: [String: AnyAssistantTool] = [:]

    public init(tools initialTools: [AnyAssistantTool] = []) throws {
        for tool in initialTools {
            if tools[tool.name] != nil {
                throw ToolExecutionError.duplicateTool(tool.name)
            }
            tools[tool.name] = tool
        }
    }

    public func register(_ tool: AnyAssistantTool) throws {
        guard tools[tool.name] == nil else {
            throw ToolExecutionError.duplicateTool(tool.name)
        }
        tools[tool.name] = tool
    }

    public func summaries() -> [ToolSummary] {
        tools.values
            .map(\.summary)
            .sorted { $0.name < $1.name }
    }

    public func run(_ invocation: ToolInvocation, confirmed: Bool = false) async throws -> ToolResult {
        guard let tool = tools[invocation.toolName] else {
            throw ToolExecutionError.unknownTool(invocation.toolName)
        }

        if tool.mutatesState && !confirmed {
            throw ToolExecutionError.confirmationRequired(tool.name)
        }

        if invocation.requiresConfirmation && !confirmed {
            throw ToolExecutionError.confirmationRequired(tool.name)
        }

        return try await tool.run(encodedArguments: invocation.encodedArguments)
    }
}
