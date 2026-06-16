import Foundation
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

@Test func auditLogCreatesHashChain() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("audit.log")
    let auditLog = AuditLog(fileURL: fileURL)

    let first = try await auditLog.append(toolName: "one", argumentsSummary: "a", resultSummary: "b")
    let second = try await auditLog.append(toolName: "two", argumentsSummary: "c", resultSummary: "d")

    #expect(first.previousHash == "genesis")
    #expect(second.previousHash == first.hash)
    #expect(try await auditLog.entries().count == 2)
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
    let keyData = Data(repeating: 7, count: 32)
    let store = EncryptedTranscriptStore(fileURL: fileURL, fixedKeyData: keyData)

    try await store.append(TranscriptRecord(request: "open calendar", response: "Opened Calendar.", toolName: "app.control"))

    let records = try await store.records()
    let rawText = try String(contentsOf: fileURL, encoding: .utf8)

    #expect(records.count == 1)
    #expect(records.first?.request == "open calendar")
    #expect(!rawText.contains("open calendar"))
    #expect(!rawText.contains("Opened Calendar."))
}

@Test func encryptedMemoryStoreSearchesWithoutPlaintext() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("memory.jsonl.enc")
    let keyData = Data(repeating: 9, count: 32)
    let store = EncryptedMemoryStore(fileURL: fileURL, fixedKeyData: keyData)

    try await store.append(MemoryRecord(content: "Prefers morning standups", tags: ["work"]))
    try await store.append(MemoryRecord(content: "Uses Neovim", tags: ["tools"]))

    let results = try await store.search(query: "neovim", limit: 5)
    let rawText = try String(contentsOf: fileURL, encoding: .utf8)

    #expect(results.map(\.content) == ["Uses Neovim"])
    #expect(!rawText.contains("Neovim"))
    #expect(!rawText.contains("standups"))
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

@Test func shellToolExecutesThroughConfiguredExecutorWhenAllowed() async throws {
    struct StubExecutor: ShellCommandExecutor {
        func run(_ command: ValidatedCommand) async throws -> String {
            "stubbed \(command.executableURL.lastPathComponent)"
        }
    }

    let allowlist = CommandAllowlist(allowedExecutablePaths: ["ls": ["/bin/ls"]])
    let tool = ShellTool(allowExecution: true, allowlist: allowlist, executor: StubExecutor())

    let result = try await tool.run(arguments: ShellTool.Arguments(command: ShellCommand(executable: "ls"), dryRun: false))

    #expect(result.metadata["dryRun"] == "false")
    #expect(result.untrustedPayload == "stubbed ls")
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
