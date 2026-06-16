import Foundation

public struct MCPToolDescriptor: Equatable, Sendable {
    public let name: String
    public let title: String?
    public let description: String?
    public let inputSchemaJSON: String

    public init(name: String, title: String?, description: String?, inputSchemaJSON: String) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchemaJSON = inputSchemaJSON
    }
}

public struct MCPToolCallResult: Equatable, Sendable {
    public let isError: Bool
    public let contentText: String

    public init(isError: Bool, contentText: String) {
        self.isError = isError
        self.contentText = contentText
    }
}

public struct MCPResourceDescriptor: Equatable, Sendable {
    public let uri: String
    public let name: String
    public let title: String?
    public let description: String?
    public let mimeType: String?

    public init(uri: String, name: String, title: String?, description: String?, mimeType: String?) {
        self.uri = uri
        self.name = name
        self.title = title
        self.description = description
        self.mimeType = mimeType
    }
}

public struct MCPResourceReadResult: Equatable, Sendable {
    public let contentText: String

    public init(contentText: String) {
        self.contentText = contentText
    }
}

public struct MCPPromptArgumentDescriptor: Equatable, Sendable {
    public let name: String
    public let description: String?
    public let required: Bool

    public init(name: String, description: String?, required: Bool) {
        self.name = name
        self.description = description
        self.required = required
    }
}

public struct MCPPromptDescriptor: Equatable, Sendable {
    public let name: String
    public let title: String?
    public let description: String?
    public let arguments: [MCPPromptArgumentDescriptor]

    public init(name: String, title: String?, description: String?, arguments: [MCPPromptArgumentDescriptor]) {
        self.name = name
        self.title = title
        self.description = description
        self.arguments = arguments
    }
}

public struct MCPPromptGetResult: Equatable, Sendable {
    public let description: String?
    public let contentText: String

    public init(description: String?, contentText: String) {
        self.description = description
        self.contentText = contentText
    }
}

public struct MCPStdioClient: Sendable {
    public let configuration: MCPServerConfiguration
    public let timeoutNanoseconds: UInt64

    public init(configuration: MCPServerConfiguration, timeoutNanoseconds: UInt64 = 10_000_000_000) {
        self.configuration = configuration
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    public func listTools() async throws -> [MCPToolDescriptor] {
        let session = MCPStdioSession(configuration: configuration, timeoutNanoseconds: timeoutNanoseconds)
        try await session.start()
        defer {
            session.close()
        }

        try await session.initialize()
        return try await session.listTools()
    }

    public func callTool(name: String, argumentsJSON: String) async throws -> MCPToolCallResult {
        let session = MCPStdioSession(configuration: configuration, timeoutNanoseconds: timeoutNanoseconds)
        try await session.start()
        defer {
            session.close()
        }

        try await session.initialize()
        return try await session.callTool(name: name, argumentsJSON: argumentsJSON)
    }

    public func listResources() async throws -> [MCPResourceDescriptor] {
        let session = MCPStdioSession(configuration: configuration, timeoutNanoseconds: timeoutNanoseconds)
        try await session.start()
        defer {
            session.close()
        }

        try await session.initialize()
        return try await session.listResources()
    }

    public func readResource(uri: String) async throws -> MCPResourceReadResult {
        let session = MCPStdioSession(configuration: configuration, timeoutNanoseconds: timeoutNanoseconds)
        try await session.start()
        defer {
            session.close()
        }

        try await session.initialize()
        return try await session.readResource(uri: uri)
    }

    public func listPrompts() async throws -> [MCPPromptDescriptor] {
        let session = MCPStdioSession(configuration: configuration, timeoutNanoseconds: timeoutNanoseconds)
        try await session.start()
        defer {
            session.close()
        }

        try await session.initialize()
        return try await session.listPrompts()
    }

    public func getPrompt(name: String, argumentsJSON: String) async throws -> MCPPromptGetResult {
        let session = MCPStdioSession(configuration: configuration, timeoutNanoseconds: timeoutNanoseconds)
        try await session.start()
        defer {
            session.close()
        }

        try await session.initialize()
        return try await session.getPrompt(name: name, argumentsJSON: argumentsJSON)
    }
}

private final class MCPStdioSession: @unchecked Sendable {
    private let configuration: MCPServerConfiguration
    private let timeoutNanoseconds: UInt64
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let readLock = NSLock()
    private let writeLock = NSLock()
    private var nextRequestID = 1

    init(configuration: MCPServerConfiguration, timeoutNanoseconds: UInt64) {
        self.configuration = configuration
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func start() async throws {
        process.executableURL = Self.executableURL(for: configuration.executable)
        process.arguments = configuration.arguments
        if let workingDirectory = configuration.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        try process.run()
    }

    func initialize() async throws {
        _ = try await request(method: "initialize", params: [
            "protocolVersion": "2025-06-18",
            "capabilities": [:],
            "clientInfo": [
                "name": "cerberus",
                "version": "0.1.0"
            ]
        ])
        try sendNotification(method: "notifications/initialized", params: nil)
    }

    func listTools() async throws -> [MCPToolDescriptor] {
        var tools: [MCPToolDescriptor] = []
        var cursor: String?

        repeat {
            let params: [String: Any]? = cursor.map { ["cursor": $0] }
            let result = try await request(method: "tools/list", params: params)
            let pageTools = result["tools"] as? [[String: Any]] ?? []
            tools += pageTools.compactMap(Self.toolDescriptor(from:))
            cursor = result["nextCursor"] as? String
        } while cursor != nil

        return tools
    }

    func callTool(name: String, argumentsJSON: String) async throws -> MCPToolCallResult {
        let arguments = try Self.jsonObject(from: argumentsJSON)
        let result = try await request(method: "tools/call", params: [
            "name": name,
            "arguments": arguments
        ])
        let isError = result["isError"] as? Bool ?? false
        let content = result["content"] as? [[String: Any]] ?? []
        let structuredContent = result["structuredContent"].map(Self.stableJSONString) ?? ""
        let text = (content.map(Self.contentText(from:)) + [structuredContent])
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return MCPToolCallResult(isError: isError, contentText: text)
    }

    func listResources() async throws -> [MCPResourceDescriptor] {
        var resources: [MCPResourceDescriptor] = []
        var cursor: String?

        repeat {
            let params: [String: Any]? = cursor.map { ["cursor": $0] }
            let result = try await request(method: "resources/list", params: params)
            let pageResources = result["resources"] as? [[String: Any]] ?? []
            resources += pageResources.compactMap(Self.resourceDescriptor(from:))
            cursor = result["nextCursor"] as? String
        } while cursor != nil

        return resources
    }

    func readResource(uri: String) async throws -> MCPResourceReadResult {
        let result = try await request(method: "resources/read", params: ["uri": uri])
        let contents = result["contents"] as? [[String: Any]] ?? []
        let text = contents.map(Self.resourceContentText(from:)).filter { !$0.isEmpty }.joined(separator: "\n")
        return MCPResourceReadResult(contentText: text)
    }

    func listPrompts() async throws -> [MCPPromptDescriptor] {
        var prompts: [MCPPromptDescriptor] = []
        var cursor: String?

        repeat {
            let params: [String: Any]? = cursor.map { ["cursor": $0] }
            let result = try await request(method: "prompts/list", params: params)
            let pagePrompts = result["prompts"] as? [[String: Any]] ?? []
            prompts += pagePrompts.compactMap(Self.promptDescriptor(from:))
            cursor = result["nextCursor"] as? String
        } while cursor != nil

        return prompts
    }

    func getPrompt(name: String, argumentsJSON: String) async throws -> MCPPromptGetResult {
        let arguments = try Self.jsonObject(from: argumentsJSON)
        var params: [String: Any] = ["name": name]
        if !arguments.isEmpty {
            params["arguments"] = arguments
        }
        let result = try await request(method: "prompts/get", params: params)
        let messages = result["messages"] as? [[String: Any]] ?? []
        let text = messages.map(Self.promptMessageText(from:)).filter { !$0.isEmpty }.joined(separator: "\n")
        return MCPPromptGetResult(description: result["description"] as? String, contentText: text)
    }

    func close() {
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
    }

    private func request(method: String, params: [String: Any]?) async throws -> [String: Any] {
        let requestID = nextRequestID
        nextRequestID += 1

        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method
        ]
        if let params {
            message["params"] = params
        }

        try send(message)

        while true {
            let response = try await readMessage()
            guard response["id"] as? Int == requestID else {
                continue
            }

            if let error = response["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "MCP request failed."
                throw ToolExecutionError.denied(message)
            }

            return response["result"] as? [String: Any] ?? [:]
        }
    }

    private func sendNotification(method: String, params: [String: Any]?) throws {
        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]
        if let params {
            message["params"] = params
        }
        try send(message)
    }

    private func send(_ message: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        var line = data
        line.append(0x0A)

        writeLock.lock()
        defer {
            writeLock.unlock()
        }
        try stdinPipe.fileHandleForWriting.write(contentsOf: line)
    }

    private func readMessage() async throws -> [String: Any] {
        let line = try await readLine()
        let object = try JSONSerialization.jsonObject(with: line)
        guard let message = object as? [String: Any] else {
            throw ToolExecutionError.invalidArguments("MCP server returned non-object JSON.")
        }
        return message
    }

    private func readLine() async throws -> Data {
        let timeout = timeoutNanoseconds

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try self.readLineBlocking()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout)
                self.close()
                throw ToolExecutionError.denied("MCP request timed out.")
            }

            let line = try await group.next() ?? Data()
            group.cancelAll()
            return line
        }
    }

    private func readLineBlocking() throws -> Data {
        readLock.lock()
        defer {
            readLock.unlock()
        }

        var line = Data()
        while true {
            guard let byte = try stdoutPipe.fileHandleForReading.read(upToCount: 1),
                  !byte.isEmpty else {
                throw ToolExecutionError.denied("MCP server closed stdout.")
            }

            if byte == Data([0x0A]) {
                return line
            }
            line.append(byte)
        }
    }

    private static func toolDescriptor(from object: [String: Any]) -> MCPToolDescriptor? {
        guard let name = object["name"] as? String else {
            return nil
        }

        return MCPToolDescriptor(
            name: name,
            title: object["title"] as? String,
            description: object["description"] as? String,
            inputSchemaJSON: stableJSONString(object["inputSchema"] ?? [:])
        )
    }

    private static func resourceDescriptor(from object: [String: Any]) -> MCPResourceDescriptor? {
        guard let uri = object["uri"] as? String else {
            return nil
        }

        return MCPResourceDescriptor(
            uri: uri,
            name: object["name"] as? String ?? uri,
            title: object["title"] as? String,
            description: object["description"] as? String,
            mimeType: object["mimeType"] as? String
        )
    }

    private static func resourceContentText(from object: [String: Any]) -> String {
        let uri = object["uri"] as? String ?? "resource"
        let mimeType = object["mimeType"] as? String ?? "unknown"
        if let text = object["text"] as? String {
            return "[\(uri)] \(mimeType)\n\(text)"
        }
        if let blob = object["blob"] as? String {
            return "[\(uri)] \(mimeType)\n[blob: \(blob.count) base64 characters]"
        }
        return stableJSONString(object)
    }

    private static func promptDescriptor(from object: [String: Any]) -> MCPPromptDescriptor? {
        guard let name = object["name"] as? String else {
            return nil
        }

        let arguments = (object["arguments"] as? [[String: Any]] ?? [])
            .compactMap(Self.promptArgumentDescriptor(from:))
        return MCPPromptDescriptor(
            name: name,
            title: object["title"] as? String,
            description: object["description"] as? String,
            arguments: arguments
        )
    }

    private static func promptArgumentDescriptor(from object: [String: Any]) -> MCPPromptArgumentDescriptor? {
        guard let name = object["name"] as? String else {
            return nil
        }

        return MCPPromptArgumentDescriptor(
            name: name,
            description: object["description"] as? String,
            required: object["required"] as? Bool ?? false
        )
    }

    private static func promptMessageText(from object: [String: Any]) -> String {
        let role = object["role"] as? String ?? "message"
        guard let content = object["content"] as? [String: Any] else {
            return "[\(role)] \(stableJSONString(object))"
        }

        let text = promptContentText(from: content)
        guard !text.isEmpty else {
            return ""
        }
        return "[\(role)] \(text)"
    }

    private static func promptContentText(from object: [String: Any]) -> String {
        switch object["type"] as? String {
        case "text":
            return object["text"] as? String ?? ""
        case "image":
            let mimeType = object["mimeType"] as? String ?? "image"
            let dataCount = (object["data"] as? String)?.count ?? 0
            return "[image: \(mimeType), \(dataCount) base64 characters]"
        case "audio":
            let mimeType = object["mimeType"] as? String ?? "audio"
            let dataCount = (object["data"] as? String)?.count ?? 0
            return "[audio: \(mimeType), \(dataCount) base64 characters]"
        case "resource":
            if let resource = object["resource"] as? [String: Any] {
                return resourceContentText(from: resource)
            }
            return stableJSONString(object)
        default:
            return stableJSONString(object)
        }
    }

    private static func contentText(from object: [String: Any]) -> String {
        switch object["type"] as? String {
        case "text":
            return object["text"] as? String ?? ""
        case "image":
            let mimeType = object["mimeType"] as? String ?? "image"
            return "[image: \(mimeType)]"
        case "audio":
            let mimeType = object["mimeType"] as? String ?? "audio"
            return "[audio: \(mimeType)]"
        case "resource_link":
            return object["uri"] as? String ?? stableJSONString(object)
        case "resource":
            return stableJSONString(object["resource"] ?? object)
        default:
            return stableJSONString(object)
        }
    }

    private static func jsonObject(from string: String) throws -> [String: Any] {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return [:]
        }

        let data = Data(trimmed.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let object = object as? [String: Any],
              JSONSerialization.isValidJSONObject(object) else {
            throw ToolExecutionError.invalidArguments("MCP arguments must be a JSON object.")
        }
        return object
    }

    private static func executableURL(for executable: String) -> URL {
        if executable.hasPrefix("/") {
            return URL(fileURLWithPath: executable)
        }

        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(executable)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return URL(fileURLWithPath: executable)
    }

    private static func stableJSONString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
}
