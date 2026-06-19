import Foundation
import FoundationModels

public protocol ShortcutsRunning: Sendable {
    func list(folderName: String?, showIdentifiers: Bool) async throws -> String
    func run(name: String, inputPath: URL?) async throws -> String
}

public struct DirectShortcutsRunner: ShortcutsRunning {
    private let executableURL: URL

    public init(executableURL: URL = URL(fileURLWithPath: "/usr/bin/shortcuts")) {
        self.executableURL = executableURL
    }

    public func list(folderName: String?, showIdentifiers: Bool) async throws -> String {
        var arguments = ["list"]
        if let folderName, !folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--folder-name", folderName]
        }
        if showIdentifiers {
            arguments.append("--show-identifiers")
        }
        return try await execute(arguments)
    }

    public func run(name: String, inputPath: URL?) async throws -> String {
        var arguments = ["run", name]
        if let inputPath {
            arguments += ["--input-path", inputPath.path]
        }
        return try await execute(arguments)
    }

    private func execute(_ arguments: [String]) async throws -> String {
        let executableURL = executableURL
        return try await Task.detached {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw ToolExecutionError.denied(error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "shortcuts failed." : error.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return output
        }.value
    }
}

public struct ShortcutsListTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let folderName: String?
        public let showIdentifiers: Bool

        public init(folderName: String? = nil, showIdentifiers: Bool = false) {
            self.folderName = folderName
            self.showIdentifiers = showIdentifiers
        }
    }

    public let name = "shortcuts.list"
    public let capability = "List existing Apple Shortcuts by name, optionally within a named folder."
    public let mutatesState = false
    public let argumentSchema = #"{"folderName":"optional folder name or none","showIdentifiers":false}"#

    private let runner: any ShortcutsRunning

    public init(runner: any ShortcutsRunning = DirectShortcutsRunner()) {
        self.runner = runner
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let output = try await runner.list(folderName: arguments.folderName, showIdentifiers: arguments.showIdentifiers)
        let shortcuts = Self.parseShortcutNames(output)
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: shortcuts.count == 1 ? "Found 1 shortcut." : "Found \(shortcuts.count) shortcuts.",
            untrustedPayload: shortcuts.isEmpty ? "No shortcuts found." : shortcuts.joined(separator: "\n"),
            metadata: ["count": "\(shortcuts.count)"]
        )
    }

    static func parseShortcutNames(_ output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

public struct ShortcutsRunTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let shortcutName: String
        public let inputText: String?

        public init(shortcutName: String, inputText: String? = nil) {
            self.shortcutName = shortcutName
            self.inputText = inputText
        }
    }

    public let name = "shortcuts.run"
    public let capability = "Run an existing Apple Shortcut by exact name or identifier. Requires explicit confirmation."
    public let mutatesState = true
    public let argumentSchema = #"{"shortcutName":"exact shortcut name or identifier","inputText":"optional text input"}"#

    private let runner: any ShortcutsRunning

    public init(runner: any ShortcutsRunning = DirectShortcutsRunner()) {
        self.runner = runner
    }

    public func validate(_ arguments: Arguments) throws {
        let trimmedName = arguments.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ToolExecutionError.invalidArguments("shortcutName is required")
        }
        if let inputText = arguments.inputText, inputText.utf8.count > 20_000 {
            throw ToolExecutionError.invalidArguments("inputText is limited to 20000 bytes")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let shortcutName = arguments.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        var inputURL: URL?
        if let inputText = arguments.inputText, !inputText.isEmpty {
            inputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("cerberus-shortcuts-\(UUID().uuidString).txt")
            try Data(inputText.utf8).write(to: inputURL!)
        }
        defer {
            if let inputURL {
                try? FileManager.default.removeItem(at: inputURL)
            }
        }

        let output = try await runner.run(name: shortcutName, inputPath: inputURL)
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Ran shortcut \(shortcutName).",
            untrustedPayload: output.trimmingCharacters(in: .whitespacesAndNewlines),
            metadata: [
                "shortcutName": shortcutName,
                "hadInput": "\(inputURL != nil)"
            ]
        )
    }
}
