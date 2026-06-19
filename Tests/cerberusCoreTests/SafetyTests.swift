import Foundation
import Security
import Testing
@testable import cerberusCore

@Test func commandAllowlistAllowsReadOnlyGitStatus() throws {
    let allowlist = CommandAllowlist(allowedExecutablePaths: ["git": ["/usr/bin/git"]])
    let command = ShellCommand(executable: "git", arguments: ["status"])

    let validated = try allowlist.validate(command)

    #expect(validated.executableURL.path == "/usr/bin/git")
    #expect(validated.arguments == ["status"])
}

@Test func commandAllowlistDeniesDangerousShellFragments() throws {
    let allowlist = CommandAllowlist(allowedExecutablePaths: ["ls": ["/bin/ls"]])
    let command = ShellCommand(executable: "ls", arguments: [";", "rm", "-rf", "/"])

    var denied = false
    do {
        _ = try allowlist.validate(command)
    } catch ToolExecutionError.denied {
        denied = true
    }

    #expect(denied)
}

@Test func commandAllowlistRejectsMutatingPackageAndVCSSubcommands() throws {
    let allowlist = CommandAllowlist(allowedExecutablePaths: [
        "brew": ["/opt/homebrew/bin/brew"],
        "git": ["/usr/bin/git"],
        "npm": ["/opt/homebrew/bin/npm"],
        "swift": ["/usr/bin/swift"]
    ])
    let commands = [
        ShellCommand(executable: "git", arguments: ["commit"]),
        ShellCommand(executable: "brew", arguments: ["install"]),
        ShellCommand(executable: "npm", arguments: ["install"]),
        ShellCommand(executable: "swift", arguments: ["package", "update"])
    ]

    for command in commands {
        #expect(throws: ToolExecutionError.self) {
            _ = try allowlist.validate(command)
        }
    }
}

@Test func commandAllowlistRejectsHomePrefixSiblingWorkingDirectory() throws {
    let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath().path
    let command = ShellCommand(executable: "pwd", workingDirectory: homePath + "-outside")

    #expect(throws: ToolExecutionError.self) {
        _ = try CommandAllowlist().validate(command)
    }
}

@Test func commandAllowlistRejectsSymlinkEscapesFromHome() throws {
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/cerberus-tests-\(UUID().uuidString)", isDirectory: true)
    let link = root.appendingPathComponent("outside-home", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: FileManager.default.temporaryDirectory)
    let command = ShellCommand(executable: "pwd", workingDirectory: link.path)

    #expect(throws: ToolExecutionError.self) {
        _ = try CommandAllowlist().validate(command)
    }
}

@Test func commandAllowlistExpandsTildeWorkingDirectory() throws {
    let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath().path
    let command = ShellCommand(executable: "pwd", workingDirectory: "~")
    let validated = try CommandAllowlist().validate(command)

    #expect(validated.workingDirectoryURL?.path == homePath)
}

@Test func auditLogCreatesHashChain() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("audit.log")
    let signingKeyData = Data(repeating: 5, count: 32)
    let auditLog = AuditLog(fileURL: fileURL, fixedSigningKeyData: signingKeyData)

    let first = try await auditLog.append(toolName: "one", argumentsSummary: "a", resultSummary: "b")
    let second = try await auditLog.append(toolName: "two", argumentsSummary: "c", resultSummary: "d")

    #expect(first.previousHash == "genesis")
    #expect(second.previousHash == first.hash)
    #expect(first.signature != nil)
    #expect(second.signature != nil)
    #expect(try await auditLog.entries().count == 2)
    #expect(try await auditLog.recentEntries(limit: 1).map(\.toolName) == ["two"])
    #expect(try await auditLog.signaturesAreValid())
    try await auditLog.deleteAll()
    #expect(try await auditLog.entries().isEmpty)
}

@Test func auditLogDetectsTamperedEntries() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("audit.log")
    let signingKeyData = Data(repeating: 7, count: 32)
    let auditLog = AuditLog(fileURL: fileURL, fixedSigningKeyData: signingKeyData)

    _ = try await auditLog.append(toolName: "calendar.read", argumentsSummary: "{}", resultSummary: "ok")
    let original = try String(contentsOf: fileURL, encoding: .utf8)
    try original.replacingOccurrences(of: "calendar.read", with: "calendar.create")
        .write(to: fileURL, atomically: true, encoding: .utf8)

    #expect(try await !auditLog.signaturesAreValid())
}

@Test func answerLastToolActionSummaryUsesSeededAuditLog() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("audit.log")
    let auditLog = AuditLog(fileURL: fileURL, fixedSigningKeyData: Data(repeating: 9, count: 32))

    _ = try await auditLog.append(toolName: "calendar.read", argumentsSummary: "today", resultSummary: "3 events")
    _ = try await auditLog.append(toolName: "mail.search", argumentsSummary: "invoice", resultSummary: "2 messages")
    let summary = AuditLogActionSummary.lastToolActionSummary(from: try await auditLog.recentEntries(limit: 5))

    #expect(summary == "Last tool call: mail.search. Result: 2 messages")
    #expect(AuditLogActionSummary.lastToolActionSummary(from: []) == "No tool calls recorded yet.")
}

@Test func voiceConfirmationParserClassifiesShortApprovalsAndDenials() {
    #expect(VoiceConfirmationParser.decision(in: "yes go ahead") == .accept)
    #expect(VoiceConfirmationParser.decision(in: "do it") == .accept)
    #expect(VoiceConfirmationParser.decision(in: "no cancel that") == .deny)
    #expect(VoiceConfirmationParser.decision(in: "maybe later") == nil)
}

@Test func encryptedTranscriptStoreRoundTripsWithoutPlaintext() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("transcripts.jsonl.enc")
    let exportURL = fileURL.deletingLastPathComponent().appendingPathComponent("transcripts.json")
    let keyData = Data(repeating: 7, count: 32)
    let store = EncryptedTranscriptStore(fileURL: fileURL, fixedKeyData: keyData)

    try await store.append(TranscriptRecord(
        request: "open calendar",
        response: "Opened Calendar.",
        toolName: "app.control",
        promptVersion: SystemPrompt.promptVersion,
        modelProfile: "default"
    ))

    let records = try await store.records()
    let rawText = try String(contentsOf: fileURL, encoding: .utf8)

    #expect(records.count == 1)
    #expect(records.first?.request == "open calendar")
    #expect(records.first?.promptVersion == SystemPrompt.promptVersion)
    #expect(records.first?.modelProfile == "default")
    #expect(!rawText.contains("open calendar"))
    #expect(!rawText.contains("Opened Calendar."))
    try await store.exportPlaintextJSON(to: exportURL)
    #expect(try String(contentsOf: exportURL, encoding: .utf8).contains("open calendar"))
    try await store.deleteAll()
    #expect(try await store.records().isEmpty)
}

@Test func encryptedMemoryStoreSearchesWithoutPlaintext() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("memory.jsonl.enc")
    let exportURL = fileURL.deletingLastPathComponent().appendingPathComponent("memory.json")
    let keyData = Data(repeating: 9, count: 32)
    let store = EncryptedMemoryStore(fileURL: fileURL, fixedKeyData: keyData)

    try await store.append(MemoryRecord(content: "Prefers morning standups", tags: ["work"]))
    try await store.append(MemoryRecord(content: "Uses Neovim", tags: ["tools"]))

    let results = try await store.search(query: "neovim", limit: 5)
    let rawText = try String(contentsOf: fileURL, encoding: .utf8)

    #expect(results.map(\.content) == ["Uses Neovim"])
    #expect(!rawText.contains("Neovim"))
    #expect(!rawText.contains("standups"))
    try await store.exportPlaintextJSON(to: exportURL)
    #expect(try String(contentsOf: exportURL, encoding: .utf8).contains("Uses Neovim"))
    try await store.deleteAll()
    #expect(try await store.records().isEmpty)
}

@Test func memoryToolsReadAndWriteEncryptedRecords() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("memory.jsonl.enc")
    let store = EncryptedMemoryStore(fileURL: fileURL, fixedKeyData: Data(repeating: 3, count: 32))
    let writeTool = MemoryWriteTool(store: store)
    let readTool = MemoryReadTool(store: store)

    _ = try await writeTool.run(arguments: MemoryWriteTool.Arguments(content: "Likes terse status updates", tags: ["preference"]))
    let result = try await readTool.run(arguments: MemoryReadTool.Arguments(query: "terse", limit: 5))

    #expect(result.spokenSummary == "Found 1 memory.")
    #expect(result.untrustedPayload.contains("Likes terse status updates"))
}

@Test func keychainSecretStoreSurfacesReadFailures() throws {
    let store = KeychainSecretStore(
        account: "read",
        operations: StubKeychainOperations(copyStatus: OSStatus(-50))
    )

    #expect(throws: KeychainSecretStoreError.osStatus(OSStatus(-50))) {
        _ = try store.data()
    }
}

@Test func keychainSecretStoreSurfacesWriteFailures() throws {
    let updateFailureStore = KeychainSecretStore(
        account: "update",
        operations: StubKeychainOperations(updateStatus: OSStatus(-50))
    )
    let addFailureStore = KeychainSecretStore(
        account: "add",
        operations: StubKeychainOperations(updateStatus: errSecItemNotFound, addStatus: OSStatus(-50))
    )

    #expect(throws: KeychainSecretStoreError.osStatus(OSStatus(-50))) {
        try updateFailureStore.save(Data("secret".utf8))
    }
    #expect(throws: KeychainSecretStoreError.osStatus(OSStatus(-50))) {
        try addFailureStore.save(Data("secret".utf8))
    }
}

@Test func keychainSecretStoreSurfacesDeleteFailures() throws {
    let store = KeychainSecretStore(
        account: "delete",
        operations: StubKeychainOperations(deleteStatus: OSStatus(-50))
    )

    #expect(throws: KeychainSecretStoreError.osStatus(OSStatus(-50))) {
        try store.delete()
    }
}

@Test func keychainDeletionForcesNewEncryptedStoreKeyAndClearRecoveryState() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("transcripts.jsonl.enc")
    let operations = InMemoryKeychainOperations()
    let keychainStore = KeychainSecretStore(account: "transcripts", operations: operations)
    let store = EncryptedTranscriptStore(fileURL: fileURL, keychainStore: keychainStore)

    try await store.append(TranscriptRecord(request: "first", response: "old key"))
    let originalKey = try #require(try keychainStore.data())
    try keychainStore.delete()

    await #expect(throws: EncryptedStoreRecoveryError.unreadableWithCurrentKey) {
        _ = try await store.records()
    }

    try await store.deleteAll()
    try await store.append(TranscriptRecord(request: "second", response: "new key"))
    let rotatedKey = try #require(try keychainStore.data())

    #expect(rotatedKey != originalKey)
    #expect(try await store.records().map(\.response) == ["new key"])
}

@Test func keychainDeletionInvalidatesOldAuditSignatures() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("audit.log")
    let operations = InMemoryKeychainOperations()
    let keychainStore = KeychainSecretStore(account: "audit", operations: operations)
    let auditLog = AuditLog(fileURL: fileURL, keychainStore: keychainStore)

    _ = try await auditLog.append(toolName: "files.search", argumentsSummary: "q", resultSummary: "ok")
    let originalKey = try #require(try keychainStore.data())
    try keychainStore.delete()
    let signaturesAreValid = try await auditLog.signaturesAreValid()

    #expect(!signaturesAreValid)
    #expect(try keychainStore.data() != originalKey)
}

@Test func mailSearchToolFormatsReadOnlyResults() async throws {
    struct StubRunner: MailSearchRunning {
        func search(
            query: String,
            mailboxName: String?,
            unreadOnly: Bool,
            includeBodySnippet: Bool,
            limit: Int
        ) async throws -> [MailMessageSnapshot] {
            [
                MailMessageSnapshot(
                    dateReceived: "Tuesday, June 16, 2026",
                    sender: "Apple <noreply@apple.com>",
                    subject: "Developer update",
                    isRead: false,
                    bodySnippet: includeBodySnippet ? "New SDK notes" : ""
                )
            ]
        }
    }

    let tool = MailSearchTool(runner: StubRunner())
    let result = try await tool.run(
        arguments: MailSearchTool.Arguments(query: "developer", includeBodySnippet: true)
    )

    #expect(result.spokenSummary == "Found 1 mail message.")
    #expect(result.untrustedPayload.contains("Apple <noreply@apple.com>"))
    #expect(result.untrustedPayload.contains("New SDK notes"))
    #expect(result.metadata["mailbox"] == "inbox")
}

@Test func mailAppleScriptRunnerParsesRows() throws {
    let rows = "Today\tAlice <a@example.com>\tSubject\tunread\tBody\nYesterday\tBob <b@example.com>\tDone\tread\t"
    let snapshots = try MailAppleScriptRunner.parseRows(rows)

    #expect(snapshots.count == 2)
    #expect(snapshots[0].subject == "Subject")
    #expect(!snapshots[0].isRead)
    #expect(snapshots[1].isRead)
}

@Test func fileSearchRejectsScopesOutsideHome() throws {
    let tool = FileSearchTool(approvedScopePaths: nil)

    #expect(throws: ToolExecutionError.self) {
        try tool.validate(FileSearchTool.Arguments(query: "README", scopePath: "/System"))
    }
}

@Test func fileSearchRequiresApprovedFolderWhenScoped() throws {
    let tool = FileSearchTool(approvedScopePaths: [])

    #expect(throws: ToolExecutionError.self) {
        try tool.validate(FileSearchTool.Arguments(query: "README"))
    }
}

@Test func fileSearchAllowsOnlyApprovedFoldersWhenScoped() throws {
    let root = try makeHomeTestDirectory()
    let approved = root.appendingPathComponent("approved", isDirectory: true)
    let child = approved.appendingPathComponent("child", isDirectory: true)
    let other = root.appendingPathComponent("other", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

    let tool = FileSearchTool(approvedScopePaths: [approved.path])

    try tool.validate(FileSearchTool.Arguments(query: "README"))
    try tool.validate(FileSearchTool.Arguments(query: "README", scopePath: child.path))
    #expect(throws: ToolExecutionError.self) {
        try tool.validate(FileSearchTool.Arguments(query: "README", scopePath: other.path))
    }
}

@Test func fileSearchScopeStorePersistsApprovedFolders() throws {
    let defaultsName = "cerberus-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer {
        defaults.removePersistentDomain(forName: defaultsName)
    }
    let root = try makeHomeTestDirectory()
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let store = FileSearchScopeStore(defaults: defaults, defaultsKey: "scopes")

    try store.add(root.path)
    try store.add(root.path + "/")

    #expect(store.approvedScopePaths() == [root.path])
    #expect(FileSearchScopeStore(defaults: defaults, defaultsKey: "scopes").approvedScopePaths() == [root.path])
}

@Test func fileSearchScopeStoreDropsInvalidPersistedFolders() throws {
    let defaultsName = "cerberus-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer {
        defaults.removePersistentDomain(forName: defaultsName)
    }
    let root = try makeHomeTestDirectory()
    defer {
        try? FileManager.default.removeItem(at: root)
    }
    defaults.set([root.path, "/System", root.appendingPathComponent("missing").path], forKey: "scopes")

    let store = FileSearchScopeStore(defaults: defaults, defaultsKey: "scopes")

    #expect(store.approvedScopePaths() == [root.path])
    #expect(defaults.stringArray(forKey: "scopes") == [root.path])
}

@Test func webSearchNormalizesAllowlistedDomains() throws {
    let tool = WebSearchTool()

    try tool.validate(WebSearchTool.Arguments(query: "swift", site: "HTTPS://Developer.Apple.com/documentation"))
    try tool.validate(WebSearchTool.Arguments(query: "swift", site: "en.wikipedia.org"))
    try tool.validate(WebSearchTool.Arguments(query: "swift", site: " developer.apple.com. "))
}

@Test func webSearchRejectsNonAllowlistedDomains() throws {
    let tool = WebSearchTool()

    #expect(throws: ToolExecutionError.self) {
        try tool.validate(WebSearchTool.Arguments(query: "swift", site: "developer.apple.com.evil.example"))
    }
    #expect(throws: ToolExecutionError.self) {
        try tool.validate(WebSearchTool.Arguments(query: "swift", site: "https://example.com/search"))
    }
    #expect(throws: ToolExecutionError.self) {
        try tool.validate(WebSearchTool.Arguments(query: "swift", site: "developer.apple.com/path"))
    }
}

@Test func shellToolExecutesThroughConfiguredExecutorWhenAllowed() async throws {
    struct StubExecutor: ShellCommandExecutor {
        func run(_ command: ValidatedCommand) async throws -> String {
            "stubbed \(command.executableURL.lastPathComponent)"
        }
    }

    let allowlist = CommandAllowlist(allowedExecutablePaths: ["ls": ["/bin/ls"]])
    let tool = ShellTool(allowExecution: true, allowlist: allowlist, executor: StubExecutor())

    let result = try await tool.run(arguments: ShellTool.Arguments(command: ShellCommand(executable: "ls")))

    #expect(result.metadata["dryRun"] == "false")
    #expect(result.untrustedPayload == "stubbed ls")
}

@Test func shellToolSummarizesGitShortStatusOutput() async throws {
    struct StubExecutor: ShellCommandExecutor {
        func run(_ command: ValidatedCommand) async throws -> String {
            " M README.md\n?? TODO.md\n"
        }
    }

    let allowlist = CommandAllowlist(allowedExecutablePaths: ["git": ["/usr/bin/git"]])
    let tool = ShellTool(allowExecution: true, allowlist: allowlist, executor: StubExecutor())

    let result = try await tool.run(
        arguments: ShellTool.Arguments(command: ShellCommand(executable: "git", arguments: ["status", "--short"]))
    )

    #expect(result.spokenSummary == "Git status shows 2 changed files.")
    #expect(result.untrustedPayload == " M README.md\n?? TODO.md\n")
}

@Test func shellToolSummarizesGitDiffOutput() async throws {
    struct StubExecutor: ShellCommandExecutor {
        func run(_ command: ValidatedCommand) async throws -> String {
            """
            diff --git a/README.md b/README.md
            +new line
            -old line
            diff --git a/TODO.md b/TODO.md
            +another line

            """
        }
    }

    let allowlist = CommandAllowlist(allowedExecutablePaths: ["git": ["/usr/bin/git"]])
    let tool = ShellTool(allowExecution: true, allowlist: allowlist, executor: StubExecutor())

    let result = try await tool.run(
        arguments: ShellTool.Arguments(command: ShellCommand(executable: "git", arguments: ["diff"]))
    )

    #expect(result.spokenSummary == "Git diff changes 2 files with 2 additions and 1 deletion.")
}

private func makeHomeTestDirectory() throws -> URL {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/cerberus-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private struct StubKeychainOperations: KeychainSecretStoreOperations {
    var copyStatus: OSStatus = errSecItemNotFound
    var copyData: Data?
    var updateStatus: OSStatus = errSecSuccess
    var addStatus: OSStatus = errSecSuccess
    var deleteStatus: OSStatus = errSecSuccess

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        (copyStatus, copyData)
    }

    func update(_ query: [String: Any], data: Data) -> OSStatus {
        updateStatus
    }

    func add(_ query: [String: Any], data: Data) -> OSStatus {
        addStatus
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        deleteStatus
    }
}

private final class InMemoryKeychainOperations: KeychainSecretStoreOperations, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = items[key(for: query)] else {
            return (errSecItemNotFound, nil)
        }
        return (errSecSuccess, data)
    }

    func update(_ query: [String: Any], data: Data) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        let key = key(for: query)
        guard items[key] != nil else {
            return errSecItemNotFound
        }
        items[key] = data
        return errSecSuccess
    }

    func add(_ query: [String: Any], data: Data) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        let key = key(for: query)
        guard items[key] == nil else {
            return errSecDuplicateItem
        }
        items[key] = data
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        items.removeValue(forKey: key(for: query))
        return errSecSuccess
    }

    private func key(for query: [String: Any]) -> String {
        "\(query[kSecAttrService as String] as? String ?? ""):\(query[kSecAttrAccount as String] as? String ?? "")"
    }
}

@Test func shellToolStillSupportsDryRun() async throws {
    struct StubExecutor: ShellCommandExecutor {
        func run(_ command: ValidatedCommand) async throws -> String {
            "should not execute"
        }
    }

    let allowlist = CommandAllowlist(allowedExecutablePaths: ["ls": ["/bin/ls"]])
    let tool = ShellTool(allowExecution: true, allowlist: allowlist, executor: StubExecutor())

    let result = try await tool.run(arguments: ShellTool.Arguments(command: ShellCommand(executable: "ls"), dryRun: true))

    #expect(result.metadata["dryRun"] == "true")
    #expect(result.untrustedPayload == "/bin/ls")
}

@Test func shellToolProposalModeForcesDryRun() async throws {
    struct StubExecutor: ShellCommandExecutor {
        func run(_ command: ValidatedCommand) async throws -> String {
            "should not execute"
        }
    }

    let allowlist = CommandAllowlist(allowedExecutablePaths: ["ls": ["/bin/ls"]])
    let tool = ShellTool(allowExecution: true, forceDryRun: { true }, allowlist: allowlist, executor: StubExecutor())

    let result = try await tool.run(arguments: ShellTool.Arguments(command: ShellCommand(executable: "ls"), dryRun: false))

    #expect(result.metadata["dryRun"] == "true")
    #expect(result.spokenSummary == "Dry run only. Command was not executed.")
}

@Test func mcpToolUsesConfiguredRunner() async throws {
    struct StubRunner: MCPToolRunning {
        func call(serverName: String, toolName: String, argumentsJSON: String) async throws -> MCPToolCallResult {
            MCPToolCallResult(isError: false, contentText: "\(serverName).\(toolName):\(argumentsJSON)")
        }
    }

    let tool = MCPTool(runner: StubRunner())
    let result = try await tool.run(
        arguments: MCPTool.Arguments(serverName: "local", toolName: "echo", argumentsJSON: #"{"text":"hello"}"#)
    )

    #expect(result.succeeded)
    #expect(result.untrustedPayload == #"local.echo:{"text":"hello"}"#)
}

@Test func mcpResourceToolsUseConfiguredRunner() async throws {
    struct StubRunner: MCPResourceRunning {
        func list(serverName: String) async throws -> [MCPResourceDescriptor] {
            [
                MCPResourceDescriptor(
                    uri: "file:///tmp/a.txt",
                    name: "a.txt",
                    title: "A",
                    description: "demo",
                    mimeType: "text/plain"
                )
            ]
        }

        func read(serverName: String, uri: String) async throws -> MCPResourceReadResult {
            MCPResourceReadResult(contentText: "[\(uri)] text/plain\nhello")
        }
    }

    let listTool = MCPResourceListTool(runner: StubRunner())
    let listResult = try await listTool.run(arguments: MCPResourceListTool.Arguments(serverName: "local"))
    let readTool = MCPResourceReadTool(runner: StubRunner())
    let readResult = try await readTool.run(
        arguments: MCPResourceReadTool.Arguments(serverName: "local", uri: "file:///tmp/a.txt")
    )

    #expect(listResult.spokenSummary == "Found 1 MCP resource.")
    #expect(listResult.untrustedPayload.contains("file:///tmp/a.txt"))
    #expect(readResult.untrustedPayload.contains("hello"))
}

@Test func mcpPromptToolsUseConfiguredRunner() async throws {
    struct StubRunner: MCPPromptRunning {
        func list(serverName: String) async throws -> [MCPPromptDescriptor] {
            [
                MCPPromptDescriptor(
                    name: "code_review",
                    title: "Code review",
                    description: "Review code",
                    arguments: [
                        MCPPromptArgumentDescriptor(name: "code", description: "Code", required: true)
                    ]
                )
            ]
        }

        func get(serverName: String, promptName: String, argumentsJSON: String) async throws -> MCPPromptGetResult {
            MCPPromptGetResult(description: "Review code", contentText: "[user] Review this")
        }
    }

    let listTool = MCPPromptListTool(runner: StubRunner())
    let listResult = try await listTool.run(arguments: MCPPromptListTool.Arguments(serverName: "local"))
    let getTool = MCPPromptGetTool(runner: StubRunner())
    let getResult = try await getTool.run(
        arguments: MCPPromptGetTool.Arguments(
            serverName: "local",
            promptName: "code_review",
            argumentsJSON: #"{"code":"print(1)"}"#
        )
    )

    #expect(listResult.spokenSummary == "Found 1 MCP prompt.")
    #expect(listResult.untrustedPayload.contains("code_review"))
    #expect(listResult.untrustedPayload.contains("code(required)"))
    #expect(getResult.untrustedPayload == "[user] Review this")
}

@Test func mcpOAuthToolsUseConfiguredRunner() async throws {
    struct StubRunner: MCPOAuthRunning {
        func discover(serverName: String) async throws -> MCPOAuthDiscoveryResult {
            MCPOAuthDiscoveryResult(
                resourceMetadataURL: URL(string: "https://example.com/.well-known/oauth-protected-resource")!,
                protectedResource: MCPOAuthProtectedResourceMetadata(
                    resource: "https://example.com/mcp",
                    authorizationServers: [URL(string: "https://auth.example.com")!],
                    scopesSupported: ["read"],
                    rawJSON: "{}"
                ),
                authorizationServer: MCPOAuthAuthorizationServerMetadata(
                    issuer: URL(string: "https://auth.example.com"),
                    authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
                    tokenEndpoint: URL(string: "https://auth.example.com/token")!,
                    registrationEndpoint: URL(string: "https://auth.example.com/register")!,
                    scopesSupported: ["read"],
                    codeChallengeMethodsSupported: ["S256"],
                    rawJSON: "{}"
                )
            )
        }

        func start(serverName: String, scopesCSV: String) async throws -> MCPOAuthStartResult {
            MCPOAuthStartResult(
                authorizationURL: URL(string: "https://auth.example.com/authorize?state=state-1")!,
                state: "state-1",
                clientID: "client-1"
            )
        }

        func exchange(serverName: String, state: String, code: String) async throws -> MCPOAuthTokenResult {
            MCPOAuthTokenResult(tokenType: "Bearer", expiresIn: 3600, scope: "read", hasRefreshToken: true)
        }

        func refresh(serverName: String) async throws -> MCPOAuthTokenResult {
            MCPOAuthTokenResult(tokenType: "Bearer", expiresIn: 3600, scope: "read", hasRefreshToken: true)
        }

        func authorizeWithLoopback(serverName: String, scopesCSV: String) async throws -> MCPOAuthTokenResult {
            MCPOAuthTokenResult(tokenType: "Bearer", expiresIn: 3600, scope: "read", hasRefreshToken: true)
        }
    }

    let runner = StubRunner()
    let discover = try await MCPOAuthDiscoverTool(runner: runner).run(
        arguments: MCPOAuthDiscoverTool.Arguments(serverName: "remote")
    )
    let start = try await MCPOAuthStartTool(runner: runner).run(
        arguments: MCPOAuthStartTool.Arguments(serverName: "remote", scopesCSV: "read")
    )
    let exchange = try await MCPOAuthExchangeTool(runner: runner).run(
        arguments: MCPOAuthExchangeTool.Arguments(serverName: "remote", state: "state-1", code: "code-1")
    )
    let refresh = try await MCPOAuthRefreshTool(runner: runner).run(
        arguments: MCPOAuthRefreshTool.Arguments(serverName: "remote")
    )
    let local = try await MCPOAuthAuthorizeLocalTool(runner: runner).run(
        arguments: MCPOAuthAuthorizeLocalTool.Arguments(serverName: "remote", scopesCSV: "read")
    )

    #expect(discover.untrustedPayload.contains("authorizationEndpoint"))
    #expect(start.untrustedPayload.contains("authorizationURL"))
    #expect(exchange.spokenSummary == "MCP OAuth token stored.")
    #expect(refresh.spokenSummary == "MCP OAuth token refreshed.")
    #expect(local.spokenSummary == "MCP OAuth browser authorization completed.")
}

@Test func mcpStdioClientRejectsUnsupportedServerSamplingAndElicitationRequests() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let scriptURL = directory.appendingPathComponent("mcp-sampling-server.sh")
    let script = """
    #!/bin/sh
    while IFS= read -r line; do
      case "$line" in
        *initialize*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"stub","version":"1"}}}'
          ;;
        *notifications*initialized*)
          ;;
        *tools*call*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":99,"method":"sampling/createMessage","params":{"messages":[{"role":"user","content":{"type":"text","text":"sample"}}],"maxTokens":10}}'
          IFS= read -r client_response
          case "$client_response" in
            *error*)
              printf '%s\\n' '{"jsonrpc":"2.0","id":100,"method":"elicitation/create","params":{"message":"name","requestedSchema":{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}}}'
              IFS= read -r elicitation_response
              case "$elicitation_response" in
                *error*)
                  printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"client requests rejected"}],"isError":false}}'
                  ;;
                *)
                  printf '%s\\n' '{"jsonrpc":"2.0","id":2,"error":{"message":"elicitation was not rejected"}}'
                  ;;
              esac
              ;;
            *)
              printf '%s\\n' '{"jsonrpc":"2.0","id":2,"error":{"message":"sampling was not rejected"}}'
              ;;
          esac
          ;;
      esac
    done
    """
    try script.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let configuration = MCPServerConfiguration(name: "stub", executable: scriptURL.path)
    let result = try await MCPStdioClient(configuration: configuration).callTool(name: "echo", argumentsJSON: "{}")

    #expect(result.contentText == "client requests rejected")
}

@Test func mcpStdioClientHandlesServerSamplingAndElicitationRequestsWithHandlers() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let scriptURL = directory.appendingPathComponent("mcp-handler-server.sh")
    let script = """
    #!/bin/sh
    while IFS= read -r line; do
      case "$line" in
        *initialize*)
          case "$line" in
            *sampling*elicitation*|*elicitation*sampling*)
              printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"stub","version":"1"}}}'
              ;;
            *)
              printf '%s\\n' '{"jsonrpc":"2.0","id":1,"error":{"message":"missing client capabilities"}}'
              ;;
          esac
          ;;
        *notifications*initialized*)
          ;;
        *tools*call*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":99,"method":"sampling/createMessage","params":{"messages":[{"role":"user","content":{"type":"text","text":"sample"}}],"maxTokens":10}}'
          IFS= read -r sampling_response
          case "$sampling_response" in
            *"sampled text"*)
              printf '%s\\n' '{"jsonrpc":"2.0","id":100,"method":"elicitation/create","params":{"message":"name","requestedSchema":{"type":"object","properties":{"name":{"type":"string","minLength":3}},"required":["name"]}}}'
              IFS= read -r elicitation_response
              case "$elicitation_response" in
                *"accept"*"octocat"*)
                  printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"client requests handled"}],"isError":false}}'
                  ;;
                *)
                  printf '%s\\n' '{"jsonrpc":"2.0","id":2,"error":{"message":"elicitation was not handled"}}'
                  ;;
              esac
              ;;
            *)
              printf '%s\\n' '{"jsonrpc":"2.0","id":2,"error":{"message":"sampling was not handled"}}'
              ;;
          esac
          ;;
      esac
    done
    """
    try script.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let handlers = MCPClientRequestHandlers(
        sampling: { request in
            #expect(request.serverName == "stub")
            #expect(request.messagesText.contains("sample"))
            #expect(request.maxTokens == 10)
            return MCPSamplingResponse(text: "sampled text", model: "cerberus-test")
        },
        elicitation: { request in
            #expect(request.serverName == "stub")
            #expect(request.message == "name")
            #expect(request.schemaJSON.contains("minLength"))
            return MCPElicitationResponse(action: .accept, contentJSON: #"{"name":"octocat"}"#)
        }
    )
    let configuration = MCPServerConfiguration(name: "stub", executable: scriptURL.path)
    let result = try await MCPStdioClient(configuration: configuration, clientRequestHandlers: handlers)
        .callTool(name: "echo", argumentsJSON: "{}")

    #expect(result.contentText == "client requests handled")
}

@Test func mcpElicitationResponseValidatesAcceptedContentAgainstSchema() throws {
    let request = MCPElicitationRequest(serverName: "stub", params: [
        "message": "age",
        "requestedSchema": [
            "type": "object",
            "properties": [
                "age": [
                    "type": "integer",
                    "minimum": 18
                ]
            ],
            "required": ["age"]
        ]
    ])

    let response = MCPElicitationResponse(action: .accept, contentJSON: #"{"age":17}"#)

    #expect(throws: ToolExecutionError.self) {
        _ = try response.resultObject(for: request)
    }
}

@Test func mcpElicitationRequestExtractsFlatSchemaFields() throws {
    let request = MCPElicitationRequest(serverName: "stub", params: [
        "message": "profile",
        "requestedSchema": [
            "type": "object",
            "properties": [
                "age": [
                    "type": "integer",
                    "minimum": 18,
                    "title": "Age"
                ],
                "notify": [
                    "type": "boolean",
                    "default": true
                ],
                "team": [
                    "type": "string",
                    "enum": ["eng", "design"],
                    "enumNames": ["Engineering", "Design"]
                ]
            ],
            "required": ["age", "team"]
        ]
    ])

    let fields = request.fields

    #expect(fields.map(\.name) == ["age", "notify", "team"])
    #expect(fields[0].type == .integer)
    #expect(fields[0].title == "Age")
    #expect(fields[0].required)
    #expect(fields[1].defaultValue == "true")
    #expect(fields[2].enumValues == ["eng", "design"])
    #expect(fields[2].enumNames == ["Engineering", "Design"])
}

@Test func mcpOAuthBuildsPKCEAuthorizationURL() throws {
    let challenge = MCPOAuthClient.codeChallenge(
        for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    )
    let url = try MCPOAuthClient.authorizationURL(
        endpoint: URL(string: "https://auth.example.com/authorize")!,
        clientID: "client-1",
        redirectURI: "http://127.0.0.1:8765/callback",
        resource: "https://example.com/mcp",
        scopes: ["read", "write"],
        codeChallenge: challenge,
        state: "state-1"
    )

    #expect(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    #expect(url.absoluteString.contains("code_challenge_method=S256"))
    #expect(url.absoluteString.contains("scope=read%20write"))
}

@Test func mcpStreamableHTTPClientCallsTools() async throws {
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var requestBodies: [String] = []

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let body = Self.bodyString(from: request)
            Self.requestBodies.append(body)

            let statusCode: Int
            let headers: [String: String]
            let responseBody: Data

            if body.contains(#""method":"initialize""#) {
                statusCode = 200
                headers = [
                    "Content-Type": "application/json",
                    "Mcp-Session-Id": "session-1"
                ]
                responseBody = Data(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"stub","version":"1"}}}"#.utf8)
            } else if body.contains(#""notifications/initialized""#) {
                statusCode = 202
                headers = [:]
                responseBody = Data()
            } else {
                statusCode = 200
                headers = ["Content-Type": "text/event-stream"]
                responseBody = Data("event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"ok\"}],\"isError\":false}}\n\n".utf8)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseBody)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private static func bodyString(from request: URLRequest) -> String {
            if let body = request.httpBody {
                return String(data: body, encoding: .utf8) ?? ""
            }

            guard let stream = request.httpBodyStream else {
                return ""
            }

            stream.open()
            defer {
                stream.close()
            }

            var data = Data()
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
            }

            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }

            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    StubURLProtocol.requestBodies = []
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [StubURLProtocol.self]
    let urlSession = URLSession(configuration: sessionConfiguration)
    let configuration = MCPServerConfiguration(
        name: "remote",
        transport: .streamableHTTP,
        endpointURL: URL(string: "https://example.com/mcp")
    )

    let result = try await MCPStreamableHTTPClient(configuration: configuration, urlSession: urlSession)
        .callTool(name: "echo", argumentsJSON: #"{"text":"hi"}"#)

    #expect(result.contentText == "ok")
    #expect(StubURLProtocol.requestBodies.count == 3)
    #expect(StubURLProtocol.requestBodies[2].contains(#""method":"tools\/call""#))
}

@Test func mcpStreamableHTTPClientHandlesSSEServerSamplingAndElicitationRequests() async throws {
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var requestBodies: [String] = []

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let body = Self.bodyString(from: request)
            Self.requestBodies.append(body)

            let statusCode: Int
            let headers: [String: String]
            let responseBody: Data

            if body.contains(#""method":"initialize""#) {
                statusCode = 200
                headers = [
                    "Content-Type": "application/json",
                    "Mcp-Session-Id": "session-1"
                ]
                responseBody = Data(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"stub","version":"1"}}}"#.utf8)
            } else if body.contains(#""notifications/initialized""#) {
                statusCode = 202
                headers = [:]
                responseBody = Data()
            } else if body.contains(#""id":99"#) || body.contains(#""id":100"#) {
                statusCode = 202
                headers = [:]
                responseBody = Data()
            } else {
                statusCode = 200
                headers = ["Content-Type": "text/event-stream"]
                responseBody = Data("""
                event: message
                data: {"jsonrpc":"2.0","id":99,"method":"sampling/createMessage","params":{"messages":[{"role":"user","content":{"type":"text","text":"sample http"}}],"maxTokens":12}}

                event: message
                data: {"jsonrpc":"2.0","id":100,"method":"elicitation/create","params":{"message":"name","requestedSchema":{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}}}

                event: message
                data: {"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"http client requests handled"}],"isError":false}}

                """.utf8)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseBody)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private static func bodyString(from request: URLRequest) -> String {
            if let body = request.httpBody {
                return String(data: body, encoding: .utf8) ?? ""
            }

            guard let stream = request.httpBodyStream else {
                return ""
            }

            stream.open()
            defer {
                stream.close()
            }

            var data = Data()
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
            }

            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }

            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    StubURLProtocol.requestBodies = []
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [StubURLProtocol.self]
    let urlSession = URLSession(configuration: sessionConfiguration)
    let configuration = MCPServerConfiguration(
        name: "remote",
        transport: .streamableHTTP,
        endpointURL: URL(string: "https://example.com/mcp")
    )
    let handlers = MCPClientRequestHandlers(
        sampling: { request in
            #expect(request.serverName == "remote")
            #expect(request.messagesText.contains("sample http"))
            #expect(request.maxTokens == 12)
            return MCPSamplingResponse(text: "sampled http", model: "cerberus-test")
        },
        elicitation: { request in
            #expect(request.serverName == "remote")
            #expect(request.message == "name")
            return MCPElicitationResponse(action: .accept, contentJSON: #"{"name":"octocat"}"#)
        }
    )

    let result = try await MCPStreamableHTTPClient(
        configuration: configuration,
        clientRequestHandlers: handlers,
        urlSession: urlSession
    ).callTool(name: "echo", argumentsJSON: "{}")

    #expect(result.contentText == "http client requests handled")
    #expect(StubURLProtocol.requestBodies.count == 5)
    #expect(StubURLProtocol.requestBodies[0].contains("sampling"))
    #expect(StubURLProtocol.requestBodies[0].contains("elicitation"))
    #expect(StubURLProtocol.requestBodies.contains { $0.contains("sampled http") })
    #expect(StubURLProtocol.requestBodies.contains { $0.contains("octocat") })
}

@Test func mcpStreamableHTTPClientListensForBackgroundSSEServerRequests() async throws {
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var requestMethods: [String] = []
        nonisolated(unsafe) static var requestBodies: [String] = []

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let method = request.httpMethod ?? ""
            let body = Self.bodyString(from: request)
            Self.requestMethods.append(method)
            Self.requestBodies.append(body)

            let statusCode: Int
            let headers: [String: String]
            let responseBody: Data

            if body.contains(#""method":"initialize""#) {
                statusCode = 200
                headers = [
                    "Content-Type": "application/json",
                    "Mcp-Session-Id": "session-1"
                ]
                responseBody = Data(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"stub","version":"1"}}}"#.utf8)
            } else if method == "POST" {
                statusCode = 202
                headers = [:]
                responseBody = Data()
            } else if method == "GET" {
                statusCode = 200
                headers = ["Content-Type": "text/event-stream"]
                responseBody = Data("""
                id: event-201
                event: message
                data: {"jsonrpc":"2.0","id":201,"method":"sampling/createMessage","params":{"messages":[{"role":"user","content":{"type":"text","text":"background sample"}}],"maxTokens":8}}

                id: event-202
                event: message
                data: {"jsonrpc":"2.0","id":202,"method":"elicitation/create","params":{"message":"team","requestedSchema":{"type":"object","properties":{"team":{"type":"string","enum":["eng"]}},"required":["team"]}}}

                """.utf8)
            } else {
                statusCode = 500
                headers = ["Content-Type": "application/json"]
                responseBody = Data(#"{"error":"unexpected"}"#.utf8)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseBody)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private static func bodyString(from request: URLRequest) -> String {
            if let body = request.httpBody {
                return String(data: body, encoding: .utf8) ?? ""
            }

            guard let stream = request.httpBodyStream else {
                return ""
            }

            stream.open()
            defer {
                stream.close()
            }

            var data = Data()
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
            }

            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }

            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    StubURLProtocol.requestMethods = []
    StubURLProtocol.requestBodies = []
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [StubURLProtocol.self]
    let urlSession = URLSession(configuration: sessionConfiguration)
    let handlers = MCPClientRequestHandlers(
        sampling: { request in
            #expect(request.messagesText.contains("background sample"))
            return MCPSamplingResponse(text: "background sampled")
        },
        elicitation: { request in
            #expect(request.fields.first?.name == "team")
            return MCPElicitationResponse(action: .accept, contentJSON: #"{"team":"eng"}"#)
        }
    )
    let client = MCPStreamableHTTPClient(
        configuration: MCPServerConfiguration(
            name: "remote",
            transport: .streamableHTTP,
            endpointURL: URL(string: "https://example.com/mcp")
        ),
        clientRequestHandlers: handlers,
        urlSession: urlSession
    )

    let result = try await client.listenForServerRequests(maxMessages: 2)

    #expect(result.endpointAvailable)
    #expect(result.handledMessages == 2)
    #expect(result.lastEventID == "event-202")
    #expect(StubURLProtocol.requestMethods == ["POST", "POST", "GET", "POST", "POST"])
}

@Test func mcpStreamableHTTPClientSendsLastEventIDForGETListener() async throws {
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var lastEventIDs: [String?] = []

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let body = Self.bodyString(from: request)
            let method = request.httpMethod ?? ""
            let statusCode: Int
            let headers: [String: String]
            let responseBody: Data

            if body.contains(#""method":"initialize""#) {
                statusCode = 200
                headers = [
                    "Content-Type": "application/json",
                    "Mcp-Session-Id": "session-1"
                ]
                responseBody = Data(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"stub","version":"1"}}}"#.utf8)
            } else if method == "GET" {
                Self.lastEventIDs.append(request.value(forHTTPHeaderField: "Last-Event-ID"))
                statusCode = 405
                headers = [:]
                responseBody = Data()
            } else {
                statusCode = 202
                headers = [:]
                responseBody = Data()
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseBody)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private static func bodyString(from request: URLRequest) -> String {
            if let body = request.httpBody {
                return String(data: body, encoding: .utf8) ?? ""
            }

            guard let stream = request.httpBodyStream else {
                return ""
            }

            stream.open()
            defer {
                stream.close()
            }

            var data = Data()
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
            }

            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }

            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    StubURLProtocol.lastEventIDs = []
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [StubURLProtocol.self]
    let urlSession = URLSession(configuration: sessionConfiguration)
    let client = MCPStreamableHTTPClient(
        configuration: MCPServerConfiguration(
            name: "remote",
            transport: .streamableHTTP,
            endpointURL: URL(string: "https://example.com/mcp")
        ),
        urlSession: urlSession
    )

    let result = try await client.listenForServerRequests(lastEventID: "event-202")

    #expect(!result.endpointAvailable)
    #expect(result.lastEventID == "event-202")
    #expect(StubURLProtocol.lastEventIDs == ["event-202"])
}

@Test func mcpHTTPListenerPolicySelectsOnlyStreamableHTTPServers() {
    let stdio = MCPServerConfiguration(name: "local", transport: .stdio, executable: "node")
    let http = MCPServerConfiguration(
        name: "remote",
        transport: .streamableHTTP,
        endpointURL: URL(string: "https://mcp.example.test")
    )

    let selectedNames = MCPHTTPListenerPolicy.listenerConfigurations(from: [stdio, http]).map(\.name)

    #expect(selectedNames == ["remote"])
}

@Test func mcpStreamableHTTPClientGetsPrompts() async throws {
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var requestBodies: [String] = []

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let body = Self.bodyString(from: request)
            Self.requestBodies.append(body)

            let statusCode: Int
            let headers: [String: String]
            let responseBody: Data

            if body.contains(#""method":"initialize""#) {
                statusCode = 200
                headers = [
                    "Content-Type": "application/json",
                    "Mcp-Session-Id": "session-1"
                ]
                responseBody = Data(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"stub","version":"1"}}}"#.utf8)
            } else if body.contains(#""notifications/initialized""#) {
                statusCode = 202
                headers = [:]
                responseBody = Data()
            } else {
                statusCode = 200
                headers = ["Content-Type": "application/json"]
                responseBody = Data(#"{"jsonrpc":"2.0","id":2,"result":{"description":"Review code","messages":[{"role":"user","content":{"type":"text","text":"Review this"}}]}}"#.utf8)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseBody)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private static func bodyString(from request: URLRequest) -> String {
            if let body = request.httpBody {
                return String(data: body, encoding: .utf8) ?? ""
            }

            guard let stream = request.httpBodyStream else {
                return ""
            }

            stream.open()
            defer {
                stream.close()
            }

            var data = Data()
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
            }

            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }

            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    StubURLProtocol.requestBodies = []
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [StubURLProtocol.self]
    let urlSession = URLSession(configuration: sessionConfiguration)
    let configuration = MCPServerConfiguration(
        name: "remote",
        transport: .streamableHTTP,
        endpointURL: URL(string: "https://example.com/mcp")
    )

    let result = try await MCPStreamableHTTPClient(configuration: configuration, urlSession: urlSession)
        .getPrompt(name: "code_review", argumentsJSON: #"{"code":"print(1)"}"#)

    #expect(result.description == "Review code")
    #expect(result.contentText == "[user] Review this")
    #expect(StubURLProtocol.requestBodies.count == 3)
    #expect(StubURLProtocol.requestBodies[2].contains(#""method":"prompts\/get""#))
    #expect(StubURLProtocol.requestBodies[2].contains(#""code":"print(1)""#))
}

@Test func mcpOAuthClientDiscoversMetadataFromWWWAuthenticate() async throws {
    final class StubURLProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let url = request.url!
            let statusCode: Int
            let headers: [String: String]
            let responseBody: Data

            if url.host == "example.com", url.path == "/mcp" {
                statusCode = 401
                headers = [
                    "WWW-Authenticate": #"Bearer resource_metadata="https://example.com/.well-known/oauth-protected-resource""#
                ]
                responseBody = Data()
            } else if url.host == "example.com" {
                statusCode = 200
                headers = ["Content-Type": "application/json"]
                responseBody = Data(#"{"resource":"https://example.com/mcp","authorization_servers":["https://auth.example.com/tenant"],"scopes_supported":["read"]}"#.utf8)
            } else {
                statusCode = 200
                headers = ["Content-Type": "application/json"]
                responseBody = Data(#"{"issuer":"https://auth.example.com/tenant","authorization_endpoint":"https://auth.example.com/authorize","token_endpoint":"https://auth.example.com/token","registration_endpoint":"https://auth.example.com/register","scopes_supported":["read"],"code_challenge_methods_supported":["S256"]}"#.utf8)
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseBody)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [StubURLProtocol.self]
    let urlSession = URLSession(configuration: sessionConfiguration)
    let configuration = MCPServerConfiguration(
        name: "remote",
        transport: .streamableHTTP,
        endpointURL: URL(string: "https://example.com/mcp")
    )

    let discovery = try await MCPOAuthClient(urlSession: urlSession).discover(configuration: configuration)

    #expect(discovery.resourceMetadataURL.absoluteString == "https://example.com/.well-known/oauth-protected-resource")
    #expect(discovery.authorizationServer.authorizationEndpoint.absoluteString == "https://auth.example.com/authorize")
    #expect(discovery.authorizationServer.registrationEndpoint?.absoluteString == "https://auth.example.com/register")
}

@Test func mcpStreamableHTTPClientAttachesStoredBearerToken() async throws {
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var authorizationHeaders: [String] = []

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            Self.authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            let body = bodyString(from: request)
            let statusCode: Int
            let headers: [String: String]
            let responseBody: Data

            if body.contains(#""method":"initialize""#) {
                statusCode = 200
                headers = [
                    "Content-Type": "application/json",
                    "Mcp-Session-Id": "session-1"
                ]
                responseBody = Data(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"stub","version":"1"}}}"#.utf8)
            } else if body.contains(#""notifications/initialized""#) {
                statusCode = 202
                headers = [:]
                responseBody = Data()
            } else {
                statusCode = 200
                headers = ["Content-Type": "application/json"]
                responseBody = Data(#"{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"ok"}],"isError":false}}"#.utf8)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseBody)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private func bodyString(from request: URLRequest) -> String {
            if let body = request.httpBody {
                return String(data: body, encoding: .utf8) ?? ""
            }

            guard let stream = request.httpBodyStream else {
                return ""
            }

            stream.open()
            defer {
                stream.close()
            }

            var data = Data()
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
            }

            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }

            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    let account = "mcp.oauth.test.\(UUID().uuidString)"
    let store = KeychainSecretStore(account: account)
    try? store.delete()
    try store.save(Data("token-1".utf8))
    defer {
        try? store.delete()
    }

    StubURLProtocol.authorizationHeaders = []
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [StubURLProtocol.self]
    let urlSession = URLSession(configuration: sessionConfiguration)
    let configuration = MCPServerConfiguration(
        name: "remote",
        transport: .streamableHTTP,
        endpointURL: URL(string: "https://example.com/mcp"),
        accessTokenKeychainAccount: account
    )

    _ = try await MCPStreamableHTTPClient(configuration: configuration, urlSession: urlSession)
        .callTool(name: "echo", argumentsJSON: "{}")

    #expect(StubURLProtocol.authorizationHeaders.count == 3)
    #expect(StubURLProtocol.authorizationHeaders.allSatisfy { $0 == "Bearer token-1" })
}

@Test func mcpStreamableHTTPClientPrefersConfiguredAuthorizationHeader() async throws {
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var authorizationHeaders: [String] = []

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            Self.authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            let body = bodyString(from: request)
            let statusCode: Int
            let headers: [String: String]
            let responseBody: Data

            if body.contains(#""method":"initialize""#) {
                statusCode = 200
                headers = [
                    "Content-Type": "application/json",
                    "Mcp-Session-Id": "session-1"
                ]
                responseBody = Data(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"stub","version":"1"}}}"#.utf8)
            } else if body.contains(#""notifications/initialized""#) {
                statusCode = 202
                headers = [:]
                responseBody = Data()
            } else {
                statusCode = 200
                headers = ["Content-Type": "application/json"]
                responseBody = Data(#"{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"ok"}],"isError":false}}"#.utf8)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseBody)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private func bodyString(from request: URLRequest) -> String {
            if let body = request.httpBody {
                return String(data: body, encoding: .utf8) ?? ""
            }

            guard let stream = request.httpBodyStream else {
                return ""
            }

            stream.open()
            defer { stream.close() }

            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
            defer { buffer.deallocate() }

            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 1024)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }

            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    let account = "mcp.oauth.test.\(UUID().uuidString)"
    let store = KeychainSecretStore(account: account)
    try? store.delete()
    try store.save(Data("stored-token".utf8))
    defer {
        try? store.delete()
    }

    StubURLProtocol.authorizationHeaders = []
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [StubURLProtocol.self]
    let urlSession = URLSession(configuration: sessionConfiguration)
    let configuration = MCPServerConfiguration(
        name: "remote",
        transport: .streamableHTTP,
        endpointURL: URL(string: "https://example.com/mcp"),
        headers: ["Authorization": "Bearer configured-token"],
        accessTokenKeychainAccount: account
    )

    _ = try await MCPStreamableHTTPClient(configuration: configuration, urlSession: urlSession)
        .callTool(name: "echo", argumentsJSON: "{}")

    #expect(StubURLProtocol.authorizationHeaders.count == 3)
    #expect(StubURLProtocol.authorizationHeaders.allSatisfy { $0 == "Bearer configured-token" })
}

@Test func mcpOAuthClientRefreshesAndRotatesStoredToken() async throws {
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var requestBody = ""

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            Self.requestBody = bodyString(from: request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let responseBody = Data(#"{"access_token":"access-2","refresh_token":"refresh-2","token_type":"Bearer","expires_in":7200,"scope":"read"}"#.utf8)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseBody)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private func bodyString(from request: URLRequest) -> String {
            if let body = request.httpBody {
                return String(data: body, encoding: .utf8) ?? ""
            }

            guard let stream = request.httpBodyStream else {
                return ""
            }

            stream.open()
            defer {
                stream.close()
            }

            var data = Data()
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
            }

            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }

            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    let service = "cerberus.tests.\(UUID().uuidString)"
    let accessAccount = "mcp.oauth.access.\(UUID().uuidString)"
    let tokenAccount = MCPOAuthKeychainAccount.tokenRecord(serverName: "remote")
    let accessStore = KeychainSecretStore(service: service, account: accessAccount)
    let tokenStore = KeychainSecretStore(service: service, account: tokenAccount)
    defer {
        try? accessStore.delete()
        try? tokenStore.delete()
    }

    let record = MCPOAuthTokenRecord(
        accessToken: "access-1",
        refreshToken: "refresh-1",
        tokenType: "Bearer",
        expiresAt: nil,
        scope: "read",
        clientID: "client-1",
        tokenEndpoint: URL(string: "https://auth.example.com/token")!,
        resource: "https://example.com/mcp"
    )
    try tokenStore.save(JSONEncoder().encode(record))

    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [StubURLProtocol.self]
    let urlSession = URLSession(configuration: sessionConfiguration)
    let configuration = MCPServerConfiguration(
        name: "remote",
        transport: .streamableHTTP,
        endpointURL: URL(string: "https://example.com/mcp"),
        accessTokenKeychainAccount: accessAccount
    )

    let result = try await MCPOAuthClient(urlSession: urlSession, keychainService: service)
        .refreshToken(configuration: configuration)
    let refreshedRecord = try JSONDecoder().decode(MCPOAuthTokenRecord.self, from: try tokenStore.data() ?? Data())
    let storedAccessToken = String(data: try accessStore.data() ?? Data(), encoding: .utf8)

    #expect(result.expiresIn == 7200)
    #expect(result.hasRefreshToken)
    #expect(StubURLProtocol.requestBody.contains("grant_type=refresh_token"))
    #expect(StubURLProtocol.requestBody.contains("refresh_token=refresh-1"))
    #expect(refreshedRecord.refreshToken == "refresh-2")
    #expect(storedAccessToken == "access-2")
}

@Test func mcpOAuthLoopbackReceiverCapturesCallback() async throws {
    let receiver = MCPOAuthLoopbackReceiver(
        preferredRedirectURI: "http://127.0.0.1:0/callback",
        timeoutNanoseconds: 5_000_000_000
    )
    let session = try await receiver.start()

    async let callback = session.waitForCallback()
    let callbackURL = URL(string: "\(session.redirectURI)?code=code-1&state=state-1")!
    let (data, response) = try await fetchLoopbackURL(callbackURL)
    let httpResponse = try #require(response as? HTTPURLResponse)
    let body = String(data: data, encoding: .utf8) ?? ""
    let result = try await callback

    #expect(httpResponse.statusCode == 200)
    #expect(body.contains("captured"))
    #expect(result.code == "code-1")
    #expect(result.state == "state-1")
}

@Test func mcpOAuthClientAuthorizesWithLocalCallback() async throws {
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var tokenRequestBody = ""

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let url = request.url!
            let responseBody: Data

            if url.host == "example.com" {
                responseBody = Data(#"{"resource":"https://example.com/mcp","authorization_servers":["https://auth.example.com"]}"#.utf8)
            } else if url.path == "/.well-known/oauth-authorization-server" {
                responseBody = Data(#"{"issuer":"https://auth.example.com","authorization_endpoint":"https://auth.example.com/authorize","token_endpoint":"https://auth.example.com/token","scopes_supported":["read"],"code_challenge_methods_supported":["S256"]}"#.utf8)
            } else {
                Self.tokenRequestBody = bodyString(from: request)
                responseBody = Data(#"{"access_token":"access-1","refresh_token":"refresh-1","token_type":"Bearer","expires_in":3600,"scope":"read"}"#.utf8)
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: responseBody)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private func bodyString(from request: URLRequest) -> String {
            if let body = request.httpBody {
                return String(data: body, encoding: .utf8) ?? ""
            }

            guard let stream = request.httpBodyStream else {
                return ""
            }

            stream.open()
            defer {
                stream.close()
            }

            var data = Data()
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
            }

            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }

            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    let service = "cerberus.tests.\(UUID().uuidString)"
    let accessAccount = "mcp.oauth.access.\(UUID().uuidString)"
    let accessStore = KeychainSecretStore(service: service, account: accessAccount)
    defer {
        try? accessStore.delete()
        try? KeychainSecretStore(service: service, account: MCPOAuthKeychainAccount.tokenRecord(serverName: "remote")).delete()
    }

    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [StubURLProtocol.self]
    let urlSession = URLSession(configuration: sessionConfiguration)
    let configuration = MCPServerConfiguration(
        name: "remote",
        transport: .streamableHTTP,
        endpointURL: URL(string: "https://example.com/mcp"),
        protectedResourceMetadataURL: URL(string: "https://example.com/.well-known/oauth-protected-resource"),
        oauthClientID: "client-1",
        oauthRedirectURI: "http://127.0.0.1:0/callback",
        oauthScopes: ["read"],
        accessTokenKeychainAccount: accessAccount
    )

    let result = try await MCPOAuthClient(urlSession: urlSession, keychainService: service)
        .authorizeWithLoopback(configuration: configuration, scopes: []) { authorizationURL in
            let components = try #require(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            let redirectURI = try #require(query["redirect_uri"])
            let state = try #require(query["state"])
            let callbackURL = URL(string: "\(redirectURI)?code=code-1&state=\(state)")!
            _ = try await fetchLoopbackURL(callbackURL)
        }
    let storedAccessToken = String(data: try accessStore.data() ?? Data(), encoding: .utf8)

    #expect(result.hasRefreshToken)
    #expect(storedAccessToken == "access-1")
    #expect(StubURLProtocol.tokenRequestBody.contains("code=code-1"))
    #expect(StubURLProtocol.tokenRequestBody.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A"))
}

@Test func mcpConfigurationDefaultsToStdioTransport() throws {
    let data = Data(#"{"servers":[{"name":"local","executable":"node","arguments":["server.js"],"workingDirectory":null}]}"#.utf8)
    let file = try JSONDecoder().decode(MCPConfigurationFile.self, from: data)

    #expect(file.servers.first?.transport == .stdio)
    #expect(file.servers.first?.executable == "node")
    #expect(file.servers.first?.oauthScopes == [])
    #expect(file.servers.first?.accessTokenKeychainAccount == nil)
}

@Test func mcpServerRegistryListsConfigurationsSortedByName() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let configURL = directory.appendingPathComponent("mcp-servers.json")
    try Data("""
    {
      "servers": [
        {"name":"zeta","transport":"stdio","executable":"/bin/echo"},
        {"name":"alpha","transport":"streamable_http","endpointURL":"https://example.com/mcp"}
      ]
    }
    """.utf8).write(to: configURL)

    let configurations = try await MCPServerRegistry(fileURL: configURL).configurations()

    #expect(configurations.map(\.name) == ["alpha", "zeta"])
    #expect(configurations[0].transport == .streamableHTTP)
}

@Test func mcpServerHealthReporterRendersPerServerLines() {
    let configurations = [
        MCPServerConfiguration(name: "local", transport: .stdio, executable: "/bin/echo"),
        MCPServerConfiguration(name: "remote", transport: .streamableHTTP, endpointURL: URL(string: "https://example.com/mcp"))
    ]

    let disabled = MCPServerHealthReporter.lines(configurations: configurations, enabled: false)
    let enabled = MCPServerHealthReporter.lines(
        configurations: configurations,
        enabled: true,
        states: ["remote": .handled],
        details: ["remote": "handled 2 background request(s)"]
    )

    #expect(disabled.map(\.state) == [.disabled, .disabled])
    #expect(enabled.map(\.name) == ["local", "remote"])
    #expect(enabled[0].displayText == "local (stdio): configured; no background listener")
    #expect(enabled[1].displayText == "remote (streamable_http): handled 2 background request(s)")
}

@Test func mcpServerRegistryRejectsBlankServerNames() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let configURL = directory.appendingPathComponent("mcp-servers.json")
    try Data(#"{"servers":[{"name":"  ","transport":"stdio","executable":"/bin/echo"}]}"#.utf8).write(to: configURL)

    await #expect(throws: ToolExecutionError.self) {
        _ = try await MCPServerRegistry(fileURL: configURL).configurations()
    }
}

@Test func mcpServerRegistryRejectsDuplicateServerNames() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let configURL = directory.appendingPathComponent("mcp-servers.json")
    try Data(#"{"servers":[{"name":"local","transport":"stdio","executable":"/bin/echo"},{"name":"local","transport":"streamable_http","endpointURL":"https://example.com/mcp"}]}"#.utf8).write(to: configURL)

    await #expect(throws: ToolExecutionError.self) {
        _ = try await MCPServerRegistry(fileURL: configURL).configurations()
    }
}

private func fetchLoopbackURL(_ url: URL) async throws -> (Data, URLResponse) {
    var lastError: (any Error)?
    for _ in 0..<5 {
        do {
            return try await URLSession.shared.data(from: url)
        } catch {
            lastError = error
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    throw lastError ?? ToolExecutionError.denied("Loopback request failed.")
}

@Test func shellExecServiceRevalidatesDeniedRequests() async {
    let service = ShellExecService()
    let request = ShellExecRequest(executable: "rm", arguments: ["-rf", "/"], workingDirectory: nil)

    await withCheckedContinuation { continuation in
        service.run(request) { response in
            #expect(!response.succeeded)
            #expect(response.errorMessage?.contains("Executable is not allowlisted") == true)
            continuation.resume()
        }
    }
}
