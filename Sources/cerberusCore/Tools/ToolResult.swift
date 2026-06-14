import Foundation

public struct ToolResult: Equatable, Sendable {
    public let toolName: String
    public let succeeded: Bool
    public let spokenSummary: String
    public let untrustedPayload: String
    public let metadata: [String: String]

    public init(
        toolName: String,
        succeeded: Bool,
        spokenSummary: String,
        untrustedPayload: String = "",
        metadata: [String: String] = [:]
    ) {
        self.toolName = toolName
        self.succeeded = succeeded
        self.spokenSummary = spokenSummary
        self.untrustedPayload = untrustedPayload
        self.metadata = metadata
    }
}

public struct ToolInvocation: Equatable, Sendable {
    public let toolName: String
    public let encodedArguments: Data
    public let requiresConfirmation: Bool

    public init<Arguments: Encodable>(
        toolName: String,
        arguments: Arguments,
        requiresConfirmation: Bool = false,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        self.toolName = toolName
        encodedArguments = try encoder.encode(arguments)
        self.requiresConfirmation = requiresConfirmation
    }
}

public enum ToolExecutionError: Error, LocalizedError, Equatable {
    case duplicateTool(String)
    case unknownTool(String)
    case confirmationRequired(String)
    case invalidArguments(String)
    case denied(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateTool(let name):
            "Tool is already registered: \(name)"
        case .unknownTool(let name):
            "Unknown tool: \(name)"
        case .confirmationRequired(let name):
            "Tool requires confirmation before execution: \(name)"
        case .invalidArguments(let message):
            "Invalid tool arguments: \(message)"
        case .denied(let message):
            message
        }
    }
}
