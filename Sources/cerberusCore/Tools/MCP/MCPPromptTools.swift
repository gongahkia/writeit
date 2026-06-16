import Foundation
import FoundationModels

public protocol MCPPromptRunning: Sendable {
    func list(serverName: String) async throws -> [MCPPromptDescriptor]
    func get(serverName: String, promptName: String, argumentsJSON: String) async throws -> MCPPromptGetResult
}

public struct MCPConfiguredPromptRunner: MCPPromptRunning {
    private let registry: MCPServerRegistry
    private let clientRequestHandlers: MCPClientRequestHandlers

    public init(
        registry: MCPServerRegistry = MCPServerRegistry(),
        clientRequestHandlers: MCPClientRequestHandlers = .none
    ) {
        self.registry = registry
        self.clientRequestHandlers = clientRequestHandlers
    }

    public func list(serverName: String) async throws -> [MCPPromptDescriptor] {
        let configuration = try await registry.configuration(named: serverName)
        switch configuration.transport {
        case .stdio:
            return try await MCPStdioClient(
                configuration: configuration,
                clientRequestHandlers: clientRequestHandlers
            ).listPrompts()
        case .streamableHTTP:
            return try await MCPStreamableHTTPClient(configuration: configuration).listPrompts()
        }
    }

    public func get(serverName: String, promptName: String, argumentsJSON: String) async throws -> MCPPromptGetResult {
        let configuration = try await registry.configuration(named: serverName)
        switch configuration.transport {
        case .stdio:
            return try await MCPStdioClient(
                configuration: configuration,
                clientRequestHandlers: clientRequestHandlers
            ).getPrompt(
                name: promptName,
                argumentsJSON: argumentsJSON
            )
        case .streamableHTTP:
            return try await MCPStreamableHTTPClient(configuration: configuration).getPrompt(
                name: promptName,
                argumentsJSON: argumentsJSON
            )
        }
    }
}

public struct MCPPromptListTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let serverName: String

        public init(serverName: String) {
            self.serverName = serverName
        }
    }

    public let name = "mcp.prompts.list"
    public let capability = "List prompt templates exposed by a configured MCP server."
    public let mutatesState = false
    public let argumentSchema = #"{"serverName":"configured-server"}"#

    private let runner: any MCPPromptRunning

    public init(runner: any MCPPromptRunning = MCPConfiguredPromptRunner()) {
        self.runner = runner
    }

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP serverName is required.")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let prompts = try await runner.list(serverName: arguments.serverName)
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: prompts.count == 1 ? "Found 1 MCP prompt." : "Found \(prompts.count) MCP prompts.",
            untrustedPayload: prompts.map(Self.format).joined(separator: "\n"),
            metadata: [
                "serverName": arguments.serverName,
                "count": "\(prompts.count)"
            ]
        )
    }

    private static func format(_ prompt: MCPPromptDescriptor) -> String {
        let displayName = prompt.title ?? prompt.name
        let description = prompt.description ?? ""
        let arguments = prompt.arguments.map { argument in
            argument.required ? "\(argument.name)(required)" : argument.name
        }
        let argumentText = arguments.isEmpty ? "" : " args: \(arguments.joined(separator: ", "))"
        return "- \(prompt.name) \(displayName) \(description)\(argumentText)"
            .trimmingCharacters(in: .whitespaces)
    }
}

public struct MCPPromptGetTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let serverName: String
        public let promptName: String
        public let argumentsJSON: String

        public init(serverName: String, promptName: String, argumentsJSON: String = "{}") {
            self.serverName = serverName
            self.promptName = promptName
            self.argumentsJSON = argumentsJSON
        }
    }

    public let name = "mcp.prompt.get"
    public let capability = "Get a prompt template by name from a configured MCP server."
    public let mutatesState = false
    public let argumentSchema = #"{"serverName":"configured-server","promptName":"prompt_name","argumentsJSON":"{}"}"#

    private let runner: any MCPPromptRunning

    public init(runner: any MCPPromptRunning = MCPConfiguredPromptRunner()) {
        self.runner = runner
    }

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP serverName is required.")
        }
        guard !arguments.promptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP promptName is required.")
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
        let result = try await runner.get(
            serverName: arguments.serverName,
            promptName: arguments.promptName,
            argumentsJSON: arguments.argumentsJSON
        )
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "MCP prompt loaded.",
            untrustedPayload: result.contentText,
            metadata: [
                "serverName": arguments.serverName,
                "promptName": arguments.promptName,
                "description": result.description ?? ""
            ]
        )
    }
}
