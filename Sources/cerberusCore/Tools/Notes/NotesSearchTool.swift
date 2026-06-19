import Foundation
import FoundationModels

public struct NoteSnapshot: Equatable, Sendable {
    public let title: String
    public let modifiedDate: String
    public let bodySnippet: String

    public init(title: String, modifiedDate: String, bodySnippet: String) {
        self.title = title
        self.modifiedDate = modifiedDate
        self.bodySnippet = bodySnippet
    }
}

public protocol NotesSearchRunning: Sendable {
    func search(query: String, includeBodySnippet: Bool, limit: Int) async throws -> [NoteSnapshot]
}

public struct NotesAppleScriptRunner: NotesSearchRunning {
    public init() {}

    public func search(query: String, includeBodySnippet: Bool, limit: Int) async throws -> [NoteSnapshot] {
        try await MainActor.run {
            guard let appleScript = NSAppleScript(source: Self.script(query: query, includeBodySnippet: includeBodySnippet, limit: limit)) else {
                throw ToolExecutionError.invalidArguments("Could not compile Notes AppleScript.")
            }
            var errorInfo: NSDictionary?
            let descriptor = appleScript.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Notes AppleScript failed."
                throw ToolExecutionError.denied(message)
            }
            return try Self.parseRows(descriptor.stringValue ?? "")
        }
    }

    private static func script(query: String, includeBodySnippet: Bool, limit: Int) -> String {
        let queryLiteral = appleScriptString(query)
        let includeBodyLiteral = includeBodySnippet ? "true" : "false"
        let limitLiteral = "\(limit)"
        return """
        on replaceText(sourceText, searchText, replacementText)
            set previousDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to searchText
            set textItems to text items of sourceText
            set AppleScript's text item delimiters to replacementText
            set outputText to textItems as text
            set AppleScript's text item delimiters to previousDelimiters
            return outputText
        end replaceText

        on cleanField(valueText)
            set cleanText to valueText as text
            set cleanText to my replaceText(cleanText, linefeed, " ")
            set cleanText to my replaceText(cleanText, return, " ")
            set cleanText to my replaceText(cleanText, tab, " ")
            return cleanText
        end cleanField

        set searchQuery to \(queryLiteral)
        set includeBodySnippet to \(includeBodyLiteral)
        set resultLimit to \(limitLiteral)
        set rows to {}

        tell application "Notes"
            repeat with noteItem in notes
                if (count of rows) is greater than or equal to resultLimit then exit repeat
                set titleText to name of noteItem as text
                set modifiedText to modification date of noteItem as text
                set bodyText to body of noteItem as text
                set snippetText to ""
                if includeBodySnippet then
                    set snippetText to bodyText
                    if (length of snippetText) is greater than 300 then set snippetText to text 1 thru 300 of snippetText
                end if

                set matchesQuery to false
                ignoring case
                    if searchQuery is "" then
                        set matchesQuery to true
                    else if titleText contains searchQuery or bodyText contains searchQuery then
                        set matchesQuery to true
                    end if
                end ignoring

                if matchesQuery then
                    set end of rows to (my cleanField(titleText) & tab & my cleanField(modifiedText) & tab & my cleanField(snippetText))
                end if
            end repeat
        end tell

        set previousDelimiters to AppleScript's text item delimiters
        set AppleScript's text item delimiters to linefeed
        set outputText to rows as text
        set AppleScript's text item delimiters to previousDelimiters
        return outputText
        """
    }

    static func parseRows(_ text: String) throws -> [NoteSnapshot] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> NoteSnapshot? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 2 else {
                    return nil
                }
                return NoteSnapshot(
                    title: fields[0],
                    modifiedDate: fields[1],
                    bodySnippet: fields.count > 2 ? fields[2] : ""
                )
            }
    }

    private static func appleScriptString(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

public struct NotesSearchTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let query: String?
        public let includeBodySnippet: Bool
        public let limit: Int

        public init(query: String? = nil, includeBodySnippet: Bool = false, limit: Int = 10) {
            self.query = query
            self.includeBodySnippet = includeBodySnippet
            self.limit = limit
        }
    }

    public let name = "notes.search"
    public let capability = "Read local Notes.app notes by title or body text, with optional body snippets."
    public let mutatesState = false
    public let argumentSchema = #"{"query":"optional title or body terms","includeBodySnippet":false,"limit":10}"#

    private let runner: any NotesSearchRunning

    public init(runner: any NotesSearchRunning = NotesAppleScriptRunner()) {
        self.runner = runner
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let query = arguments.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let limit = ToolArgumentSupport.clampLimit(arguments.limit)
        let notes = try await runner.search(
            query: query,
            includeBodySnippet: arguments.includeBodySnippet,
            limit: limit
        )
        let payload = notes
            .map { Self.format($0, includeBodySnippet: arguments.includeBodySnippet) }
            .joined(separator: "\n")
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: notes.count == 1 ? "Found 1 note." : "Found \(notes.count) notes.",
            untrustedPayload: payload,
            metadata: ["count": "\(notes.count)"]
        )
    }

    static func format(_ note: NoteSnapshot, includeBodySnippet: Bool) -> String {
        var line = "- \(note.modifiedDate) \(note.title)"
        if includeBodySnippet, !note.bodySnippet.isEmpty {
            line += " - \(note.bodySnippet)"
        }
        return line
    }
}
