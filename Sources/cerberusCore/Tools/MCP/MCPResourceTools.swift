import Foundation
import FoundationModels

public protocol MCPResourceRunning: Sendable {
    func list(serverName: String) async throws -> [MCPResourceDescriptor]
    func read(serverName: String, uri: String) async throws -> MCPResourceReadResult
}

public struct MCPConfiguredResourceRunner: MCPResourceRunning {
    private let registry: MCPServerRegistry
    private let clientRequestHandlers: MCPClientRequestHandlers

    public init(
        registry: MCPServerRegistry = MCPServerRegistry(),
        clientRequestHandlers: MCPClientRequestHandlers = .none
    ) {
        self.registry = registry
        self.clientRequestHandlers = clientRequestHandlers
    }

    public func list(serverName: String) async throws -> [MCPResourceDescriptor] {
        let configuration = try await registry.configuration(named: serverName)
        switch configuration.transport {
        case .stdio:
            return try await MCPStdioClient(
                configuration: configuration,
                clientRequestHandlers: clientRequestHandlers
            ).listResources()
        case .streamableHTTP:
            return try await MCPStreamableHTTPClient(configuration: configuration).listResources()
        }
    }

    public func read(serverName: String, uri: String) async throws -> MCPResourceReadResult {
        let configuration = try await registry.configuration(named: serverName)
        switch configuration.transport {
        case .stdio:
            return try await MCPStdioClient(
                configuration: configuration,
                clientRequestHandlers: clientRequestHandlers
            ).readResource(uri: uri)
        case .streamableHTTP:
            return try await MCPStreamableHTTPClient(configuration: configuration).readResource(uri: uri)
        }
    }
}

public struct MCPResourceListTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let serverName: String

        public init(serverName: String) {
            self.serverName = serverName
        }
    }

    public let name = "mcp.resources.list"
    public let capability = "List resources exposed by a configured MCP server."
    public let mutatesState = false
    public let argumentSchema = #"{"serverName":"configured-server"}"#

    private let runner: any MCPResourceRunning

    public init(runner: any MCPResourceRunning = MCPConfiguredResourceRunner()) {
        self.runner = runner
    }

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP serverName is required.")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let resources = try await runner.list(serverName: arguments.serverName)
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: resources.count == 1 ? "Found 1 MCP resource." : "Found \(resources.count) MCP resources.",
            untrustedPayload: resources.map(Self.format).joined(separator: "\n"),
            metadata: [
                "serverName": arguments.serverName,
                "count": "\(resources.count)"
            ]
        )
    }

    private static func format(_ resource: MCPResourceDescriptor) -> String {
        let mimeType = resource.mimeType ?? "unknown"
        let description = resource.description ?? ""
        return "- \(resource.uri) [\(mimeType)] \(resource.title ?? resource.name) \(description)"
            .trimmingCharacters(in: .whitespaces)
    }
}

public struct MCPResourceReadTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let serverName: String
        public let uri: String

        public init(serverName: String, uri: String) {
            self.serverName = serverName
            self.uri = uri
        }
    }

    public let name = "mcp.resource.read"
    public let capability = "Read a resource by URI from a configured MCP server."
    public let mutatesState = false
    public let argumentSchema = #"{"serverName":"configured-server","uri":"resource://..."}"#

    private let runner: any MCPResourceRunning

    public init(runner: any MCPResourceRunning = MCPConfiguredResourceRunner()) {
        self.runner = runner
    }

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP serverName is required.")
        }
        guard !arguments.uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP resource uri is required.")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let result = try await runner.read(serverName: arguments.serverName, uri: arguments.uri)
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "MCP resource read completed.",
            untrustedPayload: result.contentText,
            metadata: [
                "serverName": arguments.serverName,
                "uri": arguments.uri
            ]
        )
    }
}
