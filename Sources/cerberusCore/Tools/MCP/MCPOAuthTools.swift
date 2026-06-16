import Foundation
import FoundationModels

public protocol MCPOAuthRunning: Sendable {
    func discover(serverName: String) async throws -> MCPOAuthDiscoveryResult
    func start(serverName: String, scopesCSV: String) async throws -> MCPOAuthStartResult
    func exchange(serverName: String, state: String, code: String) async throws -> MCPOAuthTokenResult
}

public struct MCPConfiguredOAuthRunner: MCPOAuthRunning {
    private let registry: MCPServerRegistry
    private let client: MCPOAuthClient

    public init(registry: MCPServerRegistry = MCPServerRegistry(), client: MCPOAuthClient = MCPOAuthClient()) {
        self.registry = registry
        self.client = client
    }

    public func discover(serverName: String) async throws -> MCPOAuthDiscoveryResult {
        let configuration = try await registry.configuration(named: serverName)
        guard configuration.transport == .streamableHTTP else {
            throw ToolExecutionError.invalidArguments("MCP OAuth is only valid for Streamable HTTP servers.")
        }
        return try await client.discover(configuration: configuration)
    }

    public func start(serverName: String, scopesCSV: String) async throws -> MCPOAuthStartResult {
        let configuration = try await registry.configuration(named: serverName)
        guard configuration.transport == .streamableHTTP else {
            throw ToolExecutionError.invalidArguments("MCP OAuth is only valid for Streamable HTTP servers.")
        }
        return try await client.start(configuration: configuration, scopes: Self.scopes(from: scopesCSV))
    }

    public func exchange(serverName: String, state: String, code: String) async throws -> MCPOAuthTokenResult {
        let configuration = try await registry.configuration(named: serverName)
        guard configuration.transport == .streamableHTTP else {
            throw ToolExecutionError.invalidArguments("MCP OAuth is only valid for Streamable HTTP servers.")
        }
        return try await client.exchangeCode(configuration: configuration, state: state, code: code)
    }

    private static func scopes(from csv: String) -> [String] {
        csv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

public struct MCPOAuthDiscoverTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let serverName: String

        public init(serverName: String) {
            self.serverName = serverName
        }
    }

    public let name = "mcp.oauth.discover"
    public let capability = "Discover OAuth metadata for a configured MCP Streamable HTTP server."
    public let mutatesState = false
    public let argumentSchema = #"{"serverName":"configured-http-server"}"#

    private let runner: any MCPOAuthRunning

    public init(runner: any MCPOAuthRunning = MCPConfiguredOAuthRunner()) {
        self.runner = runner
    }

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP serverName is required.")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let result = try await runner.discover(serverName: arguments.serverName)
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "MCP OAuth metadata discovered.",
            untrustedPayload: Self.format(result),
            metadata: [
                "serverName": arguments.serverName,
                "resourceMetadataURL": result.resourceMetadataURL.absoluteString,
                "authorizationEndpoint": result.authorizationServer.authorizationEndpoint.absoluteString,
                "tokenEndpoint": result.authorizationServer.tokenEndpoint.absoluteString
            ]
        )
    }

    private static func format(_ result: MCPOAuthDiscoveryResult) -> String {
        let auth = result.authorizationServer
        return [
            "resourceMetadataURL: \(result.resourceMetadataURL.absoluteString)",
            "authorizationEndpoint: \(auth.authorizationEndpoint.absoluteString)",
            "tokenEndpoint: \(auth.tokenEndpoint.absoluteString)",
            "registrationEndpoint: \(auth.registrationEndpoint?.absoluteString ?? "")",
            "scopesSupported: \(auth.scopesSupported.joined(separator: ", "))",
            "codeChallengeMethodsSupported: \(auth.codeChallengeMethodsSupported.joined(separator: ", "))"
        ].joined(separator: "\n")
    }
}

public struct MCPOAuthStartTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let serverName: String
        public let scopesCSV: String

        public init(serverName: String, scopesCSV: String = "") {
            self.serverName = serverName
            self.scopesCSV = scopesCSV
        }
    }

    public let name = "mcp.oauth.start"
    public let capability = "Start OAuth PKCE for a configured MCP Streamable HTTP server and store verifier state in Keychain."
    public let mutatesState = true
    public let argumentSchema = #"{"serverName":"configured-http-server","scopesCSV":"optional,comma,separated"}"#

    private let runner: any MCPOAuthRunning

    public init(runner: any MCPOAuthRunning = MCPConfiguredOAuthRunner()) {
        self.runner = runner
    }

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP serverName is required.")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let result = try await runner.start(serverName: arguments.serverName, scopesCSV: arguments.scopesCSV)
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "MCP OAuth authorization URL created.",
            untrustedPayload: "authorizationURL: \(result.authorizationURL.absoluteString)\nstate: \(result.state)",
            metadata: [
                "serverName": arguments.serverName,
                "state": result.state,
                "clientID": result.clientID
            ]
        )
    }
}

public struct MCPOAuthExchangeTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let serverName: String
        public let state: String
        public let code: String

        public init(serverName: String, state: String, code: String) {
            self.serverName = serverName
            self.state = state
            self.code = code
        }
    }

    public let name = "mcp.oauth.exchange"
    public let capability = "Exchange an MCP OAuth authorization code and store the access token in Keychain."
    public let mutatesState = true
    public let argumentSchema = #"{"serverName":"configured-http-server","state":"state-from-start","code":"authorization-code"}"#

    private let runner: any MCPOAuthRunning

    public init(runner: any MCPOAuthRunning = MCPConfiguredOAuthRunner()) {
        self.runner = runner
    }

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP serverName is required.")
        }
        guard !arguments.state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP OAuth state is required.")
        }
        guard !arguments.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP OAuth code is required.")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let result = try await runner.exchange(
            serverName: arguments.serverName,
            state: arguments.state,
            code: arguments.code
        )
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "MCP OAuth token stored.",
            untrustedPayload: "tokenType: \(result.tokenType)\nexpiresIn: \(result.expiresIn.map(String.init) ?? "")\nscope: \(result.scope ?? "")",
            metadata: [
                "serverName": arguments.serverName,
                "tokenType": result.tokenType,
                "expiresIn": result.expiresIn.map(String.init) ?? ""
            ]
        )
    }
}
