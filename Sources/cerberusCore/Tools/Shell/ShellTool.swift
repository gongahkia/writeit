import Foundation

public struct ShellTool: AssistantTool {
    public struct Arguments: Codable, Sendable {
        public let command: ShellCommand
        public let dryRun: Bool

        public init(command: ShellCommand, dryRun: Bool = true) {
            self.command = command
            self.dryRun = dryRun
        }
    }

    public let name = "shell.run"
    public let capability = "Run allowlisted read-only shell commands. Defaults to dry-run."
    public let mutatesState = true
    public let argumentSchema = #"{"command":{"executable":"git","arguments":["status"],"workingDirectory":"optional path in home"},"dryRun":true}"#

    private let allowExecution: Bool
    private let allowlist: CommandAllowlist
    private let executor: any ShellCommandExecutor

    public init(
        allowExecution: Bool = false,
        allowlist: CommandAllowlist = CommandAllowlist(),
        executor: any ShellCommandExecutor = DirectShellCommandExecutor()
    ) {
        self.allowExecution = allowExecution
        self.allowlist = allowlist
        self.executor = executor
    }

    public func validate(_ arguments: Arguments) throws {
        _ = try allowlist.validate(arguments.command)
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let validated = try allowlist.validate(arguments.command)
        let commandLine = ([validated.executableURL.path] + validated.arguments).joined(separator: " ")

        guard allowExecution && !arguments.dryRun else {
            return ToolResult(
                toolName: name,
                succeeded: true,
                spokenSummary: "Dry run only. Command was not executed.",
                untrustedPayload: commandLine,
                metadata: ["dryRun": "true"]
            )
        }

        let output = try await executor.run(validated)
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Command completed.",
            untrustedPayload: output,
            metadata: ["dryRun": "false"]
        )
    }
}
