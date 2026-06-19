import Foundation
import FoundationModels

public struct LocalToolManifest: Codable, Equatable, Sendable {
    public let tools: [LocalCommandToolDefinition]

    public init(tools: [LocalCommandToolDefinition]) {
        self.tools = tools
    }
}

public struct LocalCommandToolDefinition: Codable, Equatable, Sendable {
    public let name: String
    public let capability: String
    public let command: ShellCommand

    public init(name: String, capability: String, command: ShellCommand) {
        self.name = name
        self.capability = capability
        self.command = command
    }

    public func validate() throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCapability = capability.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.hasPrefix("local."),
              trimmedName.dropFirst("local.".count).allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }) else {
            throw ToolExecutionError.invalidArguments("local tool names must start with local. and use letters, numbers, dot, underscore, or dash")
        }
        guard !trimmedCapability.isEmpty else {
            throw ToolExecutionError.invalidArguments("local tool capability is required")
        }
        _ = try CommandAllowlist().validate(command)
    }
}

public struct LocalToolManifestLoader: Sendable {
    public let manifestURL: URL
    public let decoder: JSONDecoder

    public init(
        manifestURL: URL = LocalToolManifestLoader.defaultManifestURL(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.manifestURL = manifestURL
        self.decoder = decoder
    }

    public func loadTools(shellTool: ShellTool) throws -> [AnyAssistantTool] {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return []
        }
        let data = try Data(contentsOf: manifestURL)
        let manifest = try decoder.decode(LocalToolManifest.self, from: data)
        guard manifest.tools.count <= 20 else {
            throw ToolExecutionError.invalidArguments("local tool manifest is limited to 20 tools")
        }
        return try manifest.tools.map { definition in
            try definition.validate()
            return AnyAssistantTool(LocalCommandTool(definition: definition, shellTool: shellTool))
        }
    }

    public static func defaultManifestURL() -> URL {
        CerberusDirectories.applicationSupportFile("local-tools.json")
    }
}

public struct LocalCommandTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public init() {}
    }

    public let name: String
    public let capability: String
    public let mutatesState = true
    public let argumentSchema = #"{}"#

    private let command: ShellCommand
    private let shellTool: ShellTool

    public init(definition: LocalCommandToolDefinition, shellTool: ShellTool) {
        self.name = definition.name
        self.capability = definition.capability
        self.command = definition.command
        self.shellTool = shellTool
    }

    public func validate(_ arguments: Arguments) throws {
        try shellTool.validate(ShellTool.Arguments(command: command, dryRun: false))
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let result = try await shellTool.run(arguments: ShellTool.Arguments(command: command, dryRun: false))
        return ToolResult(
            toolName: name,
            succeeded: result.succeeded,
            spokenSummary: result.spokenSummary,
            untrustedPayload: result.untrustedPayload,
            metadata: result.metadata
        )
    }
}
