import Foundation

public protocol ShellCommandExecutor: Sendable {
    func run(_ command: ValidatedCommand) async throws -> String
}

public struct DirectShellCommandExecutor: ShellCommandExecutor {
    public init() {}

    public func run(_ command: ValidatedCommand) async throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectoryURL
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        var combinedOutput = Data()
        combinedOutput.append(outputData)
        combinedOutput.append(errorData)
        let output = String(decoding: combinedOutput, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw ToolExecutionError.denied("Command exited with status \(process.terminationStatus): \(output)")
        }

        return output
    }
}
