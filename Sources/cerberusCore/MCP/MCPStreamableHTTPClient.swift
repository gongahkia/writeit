import Foundation

public struct MCPStreamableHTTPClient: Sendable {
    public let configuration: MCPServerConfiguration
    public let timeoutNanoseconds: UInt64
    private let urlSession: URLSession

    public init(
        configuration: MCPServerConfiguration,
        timeoutNanoseconds: UInt64 = 10_000_000_000,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.timeoutNanoseconds = timeoutNanoseconds
        self.urlSession = urlSession
    }

    public func listTools() async throws -> [MCPToolDescriptor] {
        let session = MCPStreamableHTTPSession(
            configuration: configuration,
            timeoutNanoseconds: timeoutNanoseconds,
            urlSession: urlSession
        )
        try await session.initialize()
        try await session.sendInitializedNotification()
        return try await session.listTools()
    }

    public func callTool(name: String, argumentsJSON: String) async throws -> MCPToolCallResult {
        let session = MCPStreamableHTTPSession(
            configuration: configuration,
            timeoutNanoseconds: timeoutNanoseconds,
            urlSession: urlSession
        )
        try await session.initialize()
        try await session.sendInitializedNotification()
        return try await session.callTool(name: name, argumentsJSON: argumentsJSON)
    }

    public func listResources() async throws -> [MCPResourceDescriptor] {
        let session = MCPStreamableHTTPSession(
            configuration: configuration,
            timeoutNanoseconds: timeoutNanoseconds,
            urlSession: urlSession
        )
        try await session.initialize()
        try await session.sendInitializedNotification()
        return try await session.listResources()
    }

    public func readResource(uri: String) async throws -> MCPResourceReadResult {
        let session = MCPStreamableHTTPSession(
            configuration: configuration,
            timeoutNanoseconds: timeoutNanoseconds,
            urlSession: urlSession
        )
        try await session.initialize()
        try await session.sendInitializedNotification()
        return try await session.readResource(uri: uri)
    }

    public func listPrompts() async throws -> [MCPPromptDescriptor] {
        let session = MCPStreamableHTTPSession(
            configuration: configuration,
            timeoutNanoseconds: timeoutNanoseconds,
            urlSession: urlSession
        )
        try await session.initialize()
        try await session.sendInitializedNotification()
        return try await session.listPrompts()
    }

    public func getPrompt(name: String, argumentsJSON: String) async throws -> MCPPromptGetResult {
        let session = MCPStreamableHTTPSession(
            configuration: configuration,
            timeoutNanoseconds: timeoutNanoseconds,
            urlSession: urlSession
        )
        try await session.initialize()
        try await session.sendInitializedNotification()
        return try await session.getPrompt(name: name, argumentsJSON: argumentsJSON)
    }
}

private final class MCPStreamableHTTPSession: @unchecked Sendable {
    private let configuration: MCPServerConfiguration
    private let timeoutNanoseconds: UInt64
    private let urlSession: URLSession
    private let protocolVersion = "2025-06-18"
    private var sessionID: String?
    private var nextRequestID = 1

    init(configuration: MCPServerConfiguration, timeoutNanoseconds: UInt64, urlSession: URLSession) {
        self.configuration = configuration
        self.timeoutNanoseconds = timeoutNanoseconds
        self.urlSession = urlSession
    }

    func initialize() async throws {
        _ = try await request(method: "initialize", params: [
            "protocolVersion": protocolVersion,
            "capabilities": [:],
            "clientInfo": [
                "name": "cerberus",
                "version": "0.1.0"
            ]
        ])
    }

    func sendInitializedNotification() async throws {
        try await notification(method: "notifications/initialized", params: nil)
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

        let response = try await post(message, expectingResponseID: requestID)
        if let error = response["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "MCP request failed."
            throw ToolExecutionError.denied(message)
        }
        return response["result"] as? [String: Any] ?? [:]
    }

    private func notification(method: String, params: [String: Any]?) async throws {
        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]
        if let params {
            message["params"] = params
        }
        _ = try await post(message, expectingResponseID: nil)
    }

    private func post(_ message: [String: Any], expectingResponseID responseID: Int?) async throws -> [String: Any] {
        guard let endpointURL = configuration.endpointURL else {
            throw ToolExecutionError.invalidArguments("MCP streamable HTTP server requires endpointURL.")
        }

        var request = URLRequest(url: endpointURL, timeoutInterval: TimeInterval(timeoutNanoseconds) / 1_000_000_000)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        for (header, value) in configuration.headers {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolExecutionError.denied("MCP HTTP server returned a non-HTTP response.")
        }

        if let nextSessionID = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id"), !nextSessionID.isEmpty {
            sessionID = nextSessionID
        }

        if responseID == nil, httpResponse.statusCode == 202 {
            return [:]
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ToolExecutionError.denied("MCP HTTP request failed with status \(httpResponse.statusCode).")
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        let responseObject: [String: Any]
        if contentType.localizedCaseInsensitiveContains("text/event-stream") {
            responseObject = try Self.jsonResponseFromSSE(data, responseID: responseID)
        } else {
            responseObject = try Self.jsonResponse(from: data)
        }

        guard let responseID else {
            return responseObject
        }

        guard responseObject["id"] as? Int == responseID else {
            throw ToolExecutionError.invalidArguments("MCP HTTP response id did not match request id.")
        }
        return responseObject
    }

    private static func jsonResponse(from data: Data) throws -> [String: Any] {
        guard !data.isEmpty else {
            return [:]
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let message = object as? [String: Any] else {
            throw ToolExecutionError.invalidArguments("MCP HTTP server returned non-object JSON.")
        }
        return message
    }

    private static func jsonResponseFromSSE(_ data: Data, responseID: Int?) throws -> [String: Any] {
        let text = String(decoding: data, as: UTF8.self)
        var eventDataLines: [String] = []

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("data:") {
                eventDataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            } else if line.isEmpty, !eventDataLines.isEmpty {
                if let message = try matchingSSEMessage(eventDataLines.joined(separator: "\n"), responseID: responseID) {
                    return message
                }
                eventDataLines = []
            }
        }

        if !eventDataLines.isEmpty,
           let message = try matchingSSEMessage(eventDataLines.joined(separator: "\n"), responseID: responseID) {
            return message
        }

        throw ToolExecutionError.invalidArguments("MCP SSE stream did not include the expected JSON-RPC response.")
    }

    private static func matchingSSEMessage(_ json: String, responseID: Int?) throws -> [String: Any]? {
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let message = object as? [String: Any] else {
            return nil
        }
        guard let responseID else {
            return message
        }
        return message["id"] as? Int == responseID ? message : nil
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

    private static func stableJSONString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
}
