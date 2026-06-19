import Foundation

public actor ToolRegistry {
    private var tools: [String: AnyAssistantTool] = [:]
    private var toolAllowlist: ToolSessionAllowlist

    public init(toolAllowlist: ToolSessionAllowlist = ToolSessionAllowlist()) {
        self.toolAllowlist = toolAllowlist
    }

    public init(tools initialTools: [AnyAssistantTool] = [], toolAllowlist: ToolSessionAllowlist = ToolSessionAllowlist()) throws {
        self.toolAllowlist = toolAllowlist
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
            .filter { toolAllowlist.isEnabled($0.name) }
            .sorted { $0.name < $1.name }
    }

    public func setToolEnabled(_ toolName: String, enabled: Bool) {
        toolAllowlist.setEnabled(toolName, enabled: enabled)
    }

    public func resetToolAllowlist() {
        toolAllowlist.reset()
    }

    public func run(_ invocation: ToolInvocation, confirmed: Bool = false) async throws -> ToolResult {
        guard toolAllowlist.isEnabled(invocation.toolName) else {
            throw ToolExecutionError.denied("\(invocation.toolName) is not enabled.")
        }

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
