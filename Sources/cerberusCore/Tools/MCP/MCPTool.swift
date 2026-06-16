import Foundation
import FoundationModels

public protocol MCPToolRunning: Sendable {
    func call(serverName: String, toolName: String, argumentsJSON: String) async throws -> MCPToolCallResult
}

public struct MCPConfiguredToolRunner: MCPToolRunning {
    private let registry: MCPServerRegistry

    public init(registry: MCPServerRegistry = MCPServerRegistry()) {
        self.registry = registry
    }

    public func call(serverName: String, toolName: String, argumentsJSON: String) async throws -> MCPToolCallResult {
        let configuration = try await registry.configuration(named: serverName)
        switch configuration.transport {
        case .stdio:
            return try await MCPStdioClient(configuration: configuration).callTool(name: toolName, argumentsJSON: argumentsJSON)
        case .streamableHTTP:
            return try await MCPStreamableHTTPClient(configuration: configuration).callTool(name: toolName, argumentsJSON: argumentsJSON)
        }
    }
}

public struct MCPTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let serverName: String
        public let toolName: String
        public let argumentsJSON: String

        public init(serverName: String, toolName: String, argumentsJSON: String = "{}") {
            self.serverName = serverName
            self.toolName = toolName
            self.argumentsJSON = argumentsJSON
        }
    }

    public let name = "mcp.call"
    public let capability = "Call a tool on a configured MCP stdio or Streamable HTTP server. Requires opt-in and confirmation."
    public let mutatesState = true
    public let argumentSchema = #"{"serverName":"configured-server","toolName":"tool_name","argumentsJSON":"{}"}"#

    private let runner: any MCPToolRunning

    public init(runner: any MCPToolRunning = MCPConfiguredToolRunner()) {
        self.runner = runner
    }

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP serverName is required.")
        }

        guard !arguments.toolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP toolName is required.")
        }

        let data = Data(arguments.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard !data.isEmpty else {
            return
        }

        do {
            guard (try JSONSerialization.jsonObject(with: data)) is [String: Any] else {
                throw ToolExecutionError.invalidArguments("MCP argumentsJSON must be a JSON object string.")
            }
        } catch let error as ToolExecutionError {
            throw error
        } catch {
            throw ToolExecutionError.invalidArguments("MCP argumentsJSON must be valid JSON.")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let result = try await runner.call(
            serverName: arguments.serverName,
            toolName: arguments.toolName,
            argumentsJSON: arguments.argumentsJSON
        )
        return ToolResult(
            toolName: name,
            succeeded: !result.isError,
            spokenSummary: result.isError ? "MCP tool returned an error." : "MCP tool completed.",
            untrustedPayload: result.contentText,
            metadata: [
                "serverName": arguments.serverName,
                "toolName": arguments.toolName
            ]
        )
    }
}
