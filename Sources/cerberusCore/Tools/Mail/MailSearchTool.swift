import Foundation
import FoundationModels

public struct MailMessageSnapshot: Equatable, Sendable {
    public let dateReceived: String
    public let sender: String
    public let subject: String
    public let isRead: Bool
    public let bodySnippet: String

    public init(dateReceived: String, sender: String, subject: String, isRead: Bool, bodySnippet: String = "") {
        self.dateReceived = dateReceived
        self.sender = sender
        self.subject = subject
        self.isRead = isRead
        self.bodySnippet = bodySnippet
    }
}

public protocol MailSearchRunning: Sendable {
    func search(
        query: String,
        mailboxName: String?,
        unreadOnly: Bool,
        includeBodySnippet: Bool,
        limit: Int
    ) async throws -> [MailMessageSnapshot]
}

public struct MailAppleScriptRunner: MailSearchRunning {
    public init() {}

    public func search(
        query: String,
        mailboxName: String?,
        unreadOnly: Bool,
        includeBodySnippet: Bool,
        limit: Int
    ) async throws -> [MailMessageSnapshot] {
        try await MainActor.run {
            let script = Self.script(
                query: query,
                mailboxName: mailboxName,
                unreadOnly: unreadOnly,
                includeBodySnippet: includeBodySnippet,
                limit: limit
            )
            guard let appleScript = NSAppleScript(source: script) else {
                throw ToolExecutionError.invalidArguments("Could not compile Mail AppleScript.")
            }

            var errorInfo: NSDictionary?
            let descriptor = appleScript.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Mail AppleScript failed."
                throw ToolExecutionError.denied(message)
            }

            return try Self.parseRows(descriptor.stringValue ?? "")
        }
    }

    private static func script(
        query: String,
        mailboxName: String?,
        unreadOnly: Bool,
        includeBodySnippet: Bool,
        limit: Int
    ) -> String {
        let queryLiteral = appleScriptString(query)
        let mailboxLiteral = appleScriptString(mailboxName ?? "")
        let unreadOnlyLiteral = unreadOnly ? "true" : "false"
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
        set requestedMailboxName to \(mailboxLiteral)
        set unreadOnly to \(unreadOnlyLiteral)
        set includeBodySnippet to \(includeBodyLiteral)
        set resultLimit to \(limitLiteral)
        set rowDelimiter to linefeed
        set rows to {}

        tell application "Mail"
            set targetMailbox to inbox
            if requestedMailboxName is not "" and requestedMailboxName is not "inbox" then
                set matchingMailboxes to every mailbox whose name is requestedMailboxName
                if (count of matchingMailboxes) is 0 then error "Mailbox not found: " & requestedMailboxName
                set targetMailbox to item 1 of matchingMailboxes
            end if

            repeat with mailMessage in messages of targetMailbox
                if (count of rows) is greater than or equal to resultLimit then exit repeat
                set subjectText to subject of mailMessage as text
                set senderText to sender of mailMessage as text
                set dateText to date received of mailMessage as text
                set isRead to read status of mailMessage
                set snippetText to ""
                if includeBodySnippet then
                    set snippetText to content of mailMessage as text
                    if (length of snippetText) is greater than 300 then set snippetText to text 1 thru 300 of snippetText
                end if

                set matchesQuery to false
                ignoring case
                    if searchQuery is "" then
                        set matchesQuery to true
                    else if subjectText contains searchQuery or senderText contains searchQuery then
                        set matchesQuery to true
                    else if includeBodySnippet and snippetText contains searchQuery then
                        set matchesQuery to true
                    end if
                end ignoring

                if unreadOnly and isRead then set matchesQuery to false
                if matchesQuery then
                    set readText to "unread"
                    if isRead then set readText to "read"
                    set end of rows to (my cleanField(dateText) & tab & my cleanField(senderText) & tab & my cleanField(subjectText) & tab & readText & tab & my cleanField(snippetText))
                end if
            end repeat
        end tell

        set previousDelimiters to AppleScript's text item delimiters
        set AppleScript's text item delimiters to rowDelimiter
        set outputText to rows as text
        set AppleScript's text item delimiters to previousDelimiters
        return outputText
        """
    }

    static func parseRows(_ text: String) throws -> [MailMessageSnapshot] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> MailMessageSnapshot? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 4 else {
                    return nil
                }

                return MailMessageSnapshot(
                    dateReceived: fields[0],
                    sender: fields[1],
                    subject: fields[2],
                    isRead: fields[3] == "read",
                    bodySnippet: fields.count > 4 ? fields[4] : ""
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

public struct MailSearchTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let query: String?
        public let mailboxName: String?
        public let unreadOnly: Bool
        public let includeBodySnippet: Bool
        public let limit: Int

        public init(
            query: String? = nil,
            mailboxName: String? = nil,
            unreadOnly: Bool = false,
            includeBodySnippet: Bool = false,
            limit: Int = 5
        ) {
            self.query = query
            self.mailboxName = mailboxName
            self.unreadOnly = unreadOnly
            self.includeBodySnippet = includeBodySnippet
            self.limit = limit
        }
    }

    public let name = "mail.search"
    public let capability = "Read recent Mail.app messages by subject or sender, with optional body snippets."
    public let mutatesState = false
    public let argumentSchema = #"{"query":"optional subject or sender terms","mailboxName":"optional mailbox, default inbox","unreadOnly":false,"includeBodySnippet":false,"limit":5}"#

    private let runner: any MailSearchRunning

    public init(runner: any MailSearchRunning = MailAppleScriptRunner()) {
        self.runner = runner
    }

    public func validate(_ arguments: Arguments) throws {
        if let mailboxName = arguments.mailboxName,
           mailboxName.rangeOfCharacter(from: .newlines) != nil {
            throw ToolExecutionError.invalidArguments("mailboxName cannot contain newlines")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let limit = ToolArgumentSupport.clampLimit(arguments.limit, default: 5, maximum: 10)
        let query = arguments.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mailboxName = arguments.mailboxName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let messages = try await runner.search(
            query: query,
            mailboxName: mailboxName?.isEmpty == true ? nil : mailboxName,
            unreadOnly: arguments.unreadOnly,
            includeBodySnippet: arguments.includeBodySnippet,
            limit: limit
        )

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: messages.count == 1 ? "Found 1 mail message." : "Found \(messages.count) mail messages.",
            untrustedPayload: messages.map(Self.format).joined(separator: "\n"),
            metadata: [
                "count": "\(messages.count)",
                "mailbox": mailboxName?.isEmpty == false ? mailboxName! : "inbox",
                "unreadOnly": "\(arguments.unreadOnly)"
            ]
        )
    }

    private static func format(_ message: MailMessageSnapshot) -> String {
        var parts = [
            "- [\(message.isRead ? "read" : "unread")]",
            message.dateReceived,
            message.sender,
            message.subject
        ]
        if !message.bodySnippet.isEmpty {
            parts.append(message.bodySnippet)
        }
        return parts.joined(separator: " | ")
    }
}
