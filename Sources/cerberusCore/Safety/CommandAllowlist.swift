import Foundation
import FoundationModels

@Generable
public struct ShellCommand: Codable, Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?

    public init(executable: String, arguments: [String] = [], workingDirectory: String? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

public struct ValidatedCommand: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let workingDirectoryURL: URL?
}

public struct CommandAllowlist: Sendable {
    private let allowedExecutablePaths: [String: [String]]

    public init(
        allowedExecutablePaths: [String: [String]] = [
            "brew": ["/opt/homebrew/bin/brew"],
            "git": ["/usr/bin/git", "/opt/homebrew/bin/git"],
            "ls": ["/bin/ls"],
            "npm": ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"],
            "pwd": ["/bin/pwd"],
            "swift": ["/usr/bin/swift"]
        ]
    ) {
        self.allowedExecutablePaths = allowedExecutablePaths
    }

    public func validate(_ command: ShellCommand) throws -> ValidatedCommand {
        let executableName = URL(fileURLWithPath: command.executable).lastPathComponent
        guard let candidatePaths = allowedExecutablePaths[executableName] else {
            throw ToolExecutionError.denied("Executable is not allowlisted: \(command.executable)")
        }

        try denyDangerousTokens([command.executable] + command.arguments)
        try validateSubcommand(executableName: executableName, arguments: command.arguments)

        guard let executablePath = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ToolExecutionError.denied("No executable path configured for \(executableName).")
        }

        return ValidatedCommand(
            executableURL: URL(fileURLWithPath: executablePath),
            arguments: command.arguments,
            workingDirectoryURL: try workingDirectoryURL(command.workingDirectory)
        )
    }

    private func validateSubcommand(executableName: String, arguments: [String]) throws {
        let firstArgument = arguments.first ?? ""

        switch executableName {
        case "git":
            let allowed = ["branch", "diff", "log", "show", "status"]
            guard allowed.contains(firstArgument) else {
                throw ToolExecutionError.denied("Only read-only git subcommands are allowed.")
            }
        case "brew":
            let allowed = ["--version", "info", "list"]
            guard allowed.contains(firstArgument) else {
                throw ToolExecutionError.denied("Only read-only brew subcommands are allowed.")
            }
        case "npm":
            let allowed = ["list", "--version"]
            guard allowed.contains(firstArgument) else {
                throw ToolExecutionError.denied("Only read-only npm subcommands are allowed.")
            }
        case "swift":
            let allowed = ["--version", "test"]
            guard allowed.contains(firstArgument) else {
                throw ToolExecutionError.denied("Only swift --version and swift test are allowed.")
            }
        case "ls", "pwd":
            return
        default:
            throw ToolExecutionError.denied("Executable has no subcommand policy: \(executableName)")
        }
    }

    private func denyDangerousTokens(_ tokens: [String]) throws {
        let deniedExactTokens = Set(["sudo", "su", "rm", "dd", "mkfs", "nc", "netcat"])
        let deniedFragments = ["-rf", ">", ">>", "|", "&&", ";", "`", "$(", "/System", "/private"]

        for token in tokens {
            if deniedExactTokens.contains(token) {
                throw ToolExecutionError.denied("Denied shell token: \(token)")
            }

            if deniedFragments.contains(where: { token.contains($0) }) {
                throw ToolExecutionError.denied("Denied shell fragment in token: \(token)")
            }
        }
    }

    private func workingDirectoryURL(_ path: String?) throws -> URL? {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: path).standardizedFileURL
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

        guard url.path.hasPrefix(homePath) else {
            throw ToolExecutionError.denied("Working directory must be inside the user's home directory.")
        }

        return url
    }
}
