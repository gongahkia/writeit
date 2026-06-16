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
    let tool = FileSearchTool()

    #expect(throws: ToolExecutionError.self) {
        try tool.validate(FileSearchTool.Arguments(query: "README", scopePath: "/System"))
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

@Test func mcpConfigurationDefaultsToStdioTransport() throws {
    let data = Data(#"{"servers":[{"name":"local","executable":"node","arguments":["server.js"],"workingDirectory":null}]}"#.utf8)
    let file = try JSONDecoder().decode(MCPConfigurationFile.self, from: data)

    #expect(file.servers.first?.transport == .stdio)
    #expect(file.servers.first?.executable == "node")
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
