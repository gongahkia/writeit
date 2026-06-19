import AppKit
import Foundation
import FoundationModels

public struct FinderSnapshot: Equatable, Sendable {
    public let frontFolderPath: String?
    public let selectedPaths: [String]

    public init(frontFolderPath: String?, selectedPaths: [String]) {
        self.frontFolderPath = frontFolderPath
        self.selectedPaths = selectedPaths
    }
}

public protocol FinderSelectionRunning: Sendable {
    func snapshot() async throws -> FinderSnapshot
}

public protocol FinderRevealRunning: Sendable {
    func reveal(path: String) async throws -> String
}

public struct FinderAppleScriptSelectionRunner: FinderSelectionRunning {
    public init() {}

    public func snapshot() async throws -> FinderSnapshot {
        try await MainActor.run {
            guard let script = NSAppleScript(source: Self.script) else {
                throw ToolExecutionError.denied("Could not prepare Finder automation script.")
            }

            var errorInfo: NSDictionary?
            let output = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Finder AppleScript failed."
                throw ToolExecutionError.denied(message)
            }
            return Self.parse(output.stringValue ?? "")
        }
    }

    static func parse(_ text: String) -> FinderSnapshot {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let frontFolder = lines.first.flatMap { $0.isEmpty ? nil : $0 }
        let selectedPaths = lines.dropFirst().filter { !$0.isEmpty }
        return FinderSnapshot(frontFolderPath: frontFolder, selectedPaths: selectedPaths)
    }

    private static let script = """
    set outputRows to {}
    set frontFolderPath to ""

    tell application "Finder"
        try
            if (count of Finder windows) is greater than 0 then
                set frontFolderPath to POSIX path of (target of front Finder window as alias)
            end if
        end try

        set end of outputRows to frontFolderPath
        repeat with selectedItem in selection
            try
                set end of outputRows to POSIX path of (selectedItem as alias)
            end try
        end repeat
    end tell

    set previousDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to linefeed
    set outputText to outputRows as text
    set AppleScript's text item delimiters to previousDelimiters
    return outputText
    """
}

public struct FinderWorkspaceRevealRunner: FinderRevealRunning {
    public init() {}

    public func reveal(path: String) async throws -> String {
        let url = try Self.existingFileURL(path)
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        return "Revealed \(url.path) in Finder."
    }

    static func existingFileURL(_ path: String) throws -> URL {
        let expandedPath = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
            .expandingTildeInPath
        guard !expandedPath.isEmpty else {
            throw ToolExecutionError.invalidArguments("path is required")
        }

        let url = URL(fileURLWithPath: expandedPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolExecutionError.denied("Path does not exist.")
        }
        return url
    }
}

public struct FinderSelectionTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public init() {}
    }

    public let name = "finder.selection"
    public let capability = "Read the front Finder folder and selected Finder item paths."
    public let mutatesState = false
    public let argumentSchema = #"{}"#

    private let runner: any FinderSelectionRunning

    public init(runner: any FinderSelectionRunning = FinderAppleScriptSelectionRunner()) {
        self.runner = runner
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let snapshot = try await runner.snapshot()
        var lines = ["Front folder: \(snapshot.frontFolderPath ?? "No Finder window")"]
        if snapshot.selectedPaths.isEmpty {
            lines.append("Selected items: none")
        } else {
            lines.append("Selected items:")
            lines += snapshot.selectedPaths.map { "- \($0)" }
        }

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: snapshot.selectedPaths.count == 1
                ? "Finder has 1 selected item."
                : "Finder has \(snapshot.selectedPaths.count) selected items.",
            untrustedPayload: lines.joined(separator: "\n"),
            metadata: [
                "selectedCount": "\(snapshot.selectedPaths.count)",
                "frontFolderPath": snapshot.frontFolderPath ?? ""
            ]
        )
    }
}

public struct FinderRevealTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let path: String

        public init(path: String) {
            self.path = path
        }
    }

    public let name = "finder.reveal"
    public let capability = "Reveal an existing file or folder path in Finder. Requires explicit confirmation."
    public let mutatesState = true
    public let argumentSchema = #"{"path":"existing file or folder path"}"#

    private let runner: any FinderRevealRunning

    public init(runner: any FinderRevealRunning = FinderWorkspaceRevealRunner()) {
        self.runner = runner
    }

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("path is required")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let summary = try await runner.reveal(path: arguments.path)
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: summary,
            untrustedPayload: summary
        )
    }
}
