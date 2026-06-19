import Foundation

public struct MCPStreamableHTTPListenResult: Equatable, Sendable {
    public let serverName: String
    public let endpointAvailable: Bool
    public let handledMessages: Int
    public let lastEventID: String?

    public init(serverName: String, endpointAvailable: Bool, handledMessages: Int, lastEventID: String? = nil) {
        self.serverName = serverName
        self.endpointAvailable = endpointAvailable
        self.handledMessages = handledMessages
        self.lastEventID = lastEventID
    }
}

public struct MCPStreamableHTTPClient: Sendable {
    public let configuration: MCPServerConfiguration
    public let timeoutNanoseconds: UInt64
    public let clientRequestHandlers: MCPClientRequestHandlers
    private let urlSession: URLSession

    public init(
        configuration: MCPServerConfiguration,
        timeoutNanoseconds: UInt64 = 10_000_000_000,
        clientRequestHandlers: MCPClientRequestHandlers = .none,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.timeoutNanoseconds = timeoutNanoseconds
        self.clientRequestHandlers = clientRequestHandlers
        self.urlSession = urlSession
    }

    public func listTools() async throws -> [MCPToolDescriptor] {
        let session = MCPStreamableHTTPSession(
            configuration: configuration,
            timeoutNanoseconds: timeoutNanoseconds,
            clientRequestHandlers: clientRequestHandlers,
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
            clientRequestHandlers: clientRequestHandlers,
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
            clientRequestHandlers: clientRequestHandlers,
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
            clientRequestHandlers: clientRequestHandlers,
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
            clientRequestHandlers: clientRequestHandlers,
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
            clientRequestHandlers: clientRequestHandlers,
            urlSession: urlSession
        )
        try await session.initialize()
        try await session.sendInitializedNotification()
        return try await session.getPrompt(name: name, argumentsJSON: argumentsJSON)
    }

    public func listenForServerRequests(maxMessages: Int? = nil, lastEventID: String? = nil) async throws -> MCPStreamableHTTPListenResult {
        let session = MCPStreamableHTTPSession(
            configuration: configuration,
            timeoutNanoseconds: timeoutNanoseconds,
            clientRequestHandlers: clientRequestHandlers,
            urlSession: urlSession
        )
        try await session.initialize()
        try await session.sendInitializedNotification()
        return try await session.listenForServerRequests(maxMessages: maxMessages, lastEventID: lastEventID)
    }
}

private final class MCPStreamableHTTPSession: @unchecked Sendable {
    private let configuration: MCPServerConfiguration
    private let timeoutNanoseconds: UInt64
    private let clientRequestHandlers: MCPClientRequestHandlers
    private let urlSession: URLSession
    private let protocolVersion = "2025-06-18"
    private var sessionID: String?
    private var nextRequestID = 1

    init(
        configuration: MCPServerConfiguration,
        timeoutNanoseconds: UInt64,
        clientRequestHandlers: MCPClientRequestHandlers,
        urlSession: URLSession
    ) {
        self.configuration = configuration
        self.timeoutNanoseconds = timeoutNanoseconds
        self.clientRequestHandlers = clientRequestHandlers
        self.urlSession = urlSession
    }

    func initialize() async throws {
        _ = try await request(method: "initialize", params: [
            "protocolVersion": protocolVersion,
            "capabilities": clientRequestHandlers.capabilities,
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

    func listenForServerRequests(maxMessages: Int?, lastEventID: String?) async throws -> MCPStreamableHTTPListenResult {
        guard let endpointURL = configuration.endpointURL else {
            throw ToolExecutionError.invalidArguments("MCP streamable HTTP server requires endpointURL.")
        }

        var request = URLRequest(url: endpointURL, timeoutInterval: TimeInterval(timeoutNanoseconds) / 1_000_000_000)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        if let lastEventID, !lastEventID.isEmpty {
            request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
        }
        try applyAuthorizationHeaders(to: &request)

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolExecutionError.denied("MCP HTTP server returned a non-HTTP response.")
        }

        if httpResponse.statusCode == 405 {
            return MCPStreamableHTTPListenResult(
                serverName: configuration.name,
                endpointAvailable: false,
                handledMessages: 0,
                lastEventID: lastEventID
            )
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ToolExecutionError.denied("MCP HTTP listener failed with status \(httpResponse.statusCode).")
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard contentType.localizedCaseInsensitiveContains("text/event-stream") else {
            throw ToolExecutionError.invalidArguments("MCP HTTP listener did not return an SSE stream.")
        }

        let listenerState = try await handleServerEventsFromSSE(bytes, maxMessages: maxMessages)
        return MCPStreamableHTTPListenResult(
            serverName: configuration.name,
            endpointAvailable: true,
            handledMessages: listenerState.handledMessages,
            lastEventID: listenerState.lastEventID ?? lastEventID
        )
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
        try applyAuthorizationHeaders(to: &request)

        let (bytes, response) = try await urlSession.bytes(for: request)
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
            responseObject = try await jsonResponseFromSSE(bytes, responseID: responseID)
        } else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }
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

    private struct SSEListenerState: Equatable {
        var handledMessages: Int
        var lastEventID: String?
    }

    private func handleServerEventsFromSSE(_ bytes: URLSession.AsyncBytes, maxMessages: Int?) async throws -> SSEListenerState {
        var eventDataLines: [String] = []
        var lineBytes: [UInt8] = []
        var handledMessages = 0
        var currentEventID: String?
        var lastEventID: String?

        func processLine(_ line: String) async throws -> Bool {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.hasPrefix("data:") {
                eventDataLines.append(String(trimmedLine.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            } else if trimmedLine.hasPrefix("id:") {
                currentEventID = String(trimmedLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if trimmedLine.isEmpty, !eventDataLines.isEmpty {
                if try await handleSSEServerEvent(eventDataLines.joined(separator: "\n")) {
                    handledMessages += 1
                }
                lastEventID = currentEventID ?? lastEventID
                currentEventID = nil
                eventDataLines = []
            }
            return maxMessages.map { handledMessages >= $0 } ?? false
        }

        for try await byte in bytes {
            if byte == 0x0A {
                let line = String(decoding: lineBytes, as: UTF8.self)
                if try await processLine(line) {
                    return SSEListenerState(handledMessages: handledMessages, lastEventID: lastEventID)
                }
                lineBytes.removeAll(keepingCapacity: true)
            } else {
                lineBytes.append(byte)
            }
        }

        if !lineBytes.isEmpty {
            let line = String(decoding: lineBytes, as: UTF8.self)
            if try await processLine(line) {
                return SSEListenerState(handledMessages: handledMessages, lastEventID: lastEventID)
            }
        }

        if !eventDataLines.isEmpty,
           try await handleSSEServerEvent(eventDataLines.joined(separator: "\n")) {
            handledMessages += 1
            lastEventID = currentEventID ?? lastEventID
        }

        return SSEListenerState(handledMessages: handledMessages, lastEventID: lastEventID)
    }

    private func jsonResponseFromSSE(_ bytes: URLSession.AsyncBytes, responseID: Int?) async throws -> [String: Any] {
        var eventDataLines: [String] = []
        var lineBytes: [UInt8] = []

        func processLine(_ line: String) async throws -> [String: Any]? {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.hasPrefix("data:") {
                eventDataLines.append(String(trimmedLine.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            } else if trimmedLine.isEmpty, !eventDataLines.isEmpty {
                if let message = try await matchingSSEMessage(eventDataLines.joined(separator: "\n"), responseID: responseID) {
                    return message
                }
                eventDataLines = []
            }
            return nil
        }

        for try await byte in bytes {
            if byte == 0x0A {
                let line = String(decoding: lineBytes, as: UTF8.self)
                if let message = try await processLine(line) {
                    return message
                }
                lineBytes.removeAll(keepingCapacity: true)
            } else {
                lineBytes.append(byte)
            }
        }

        if !lineBytes.isEmpty {
            let line = String(decoding: lineBytes, as: UTF8.self)
            if let message = try await processLine(line) {
                return message
            }
        }

        if !eventDataLines.isEmpty,
           let message = try await matchingSSEMessage(eventDataLines.joined(separator: "\n"), responseID: responseID) {
            return message
        }

        throw ToolExecutionError.invalidArguments("MCP SSE stream did not include the expected JSON-RPC response.")
    }

    private func handleSSEServerEvent(_ json: String) async throws -> Bool {
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let message = object as? [String: Any] else {
            return false
        }
        return try await handleServerRequestIfNeeded(message)
    }

    private func matchingSSEMessage(_ json: String, responseID: Int?) async throws -> [String: Any]? {
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let message = object as? [String: Any] else {
            return nil
        }
        guard let responseID else {
            return message
        }
        if message["id"] as? Int == responseID {
            return message
        }

        _ = try await handleServerRequestIfNeeded(message)
        return nil
    }

    private func handleServerRequestIfNeeded(_ message: [String: Any]) async throws -> Bool {
        guard let id = message["id"],
              let method = message["method"] as? String else {
            return false
        }

        switch method {
        case "sampling/createMessage":
            try await handleSamplingRequest(id: id, params: message["params"] as? [String: Any] ?? [:])
        case "elicitation/create":
            try await handleElicitationRequest(id: id, params: message["params"] as? [String: Any] ?? [:])
        default:
            try await sendErrorResponse(
                id: id,
                code: -32601,
                message: "MCP client method is not supported by cerberus: \(method)"
            )
        }
        return true
    }

    private func handleSamplingRequest(id: Any, params: [String: Any]) async throws {
        guard let sampling = clientRequestHandlers.sampling else {
            try await sendErrorResponse(
                id: id,
                code: -32000,
                message: "MCP sampling is not supported by cerberus."
            )
            return
        }

        do {
            let request = MCPSamplingRequest(serverName: configuration.name, params: params)
            let response = try await sampling(request)
            try await sendResultResponse(id: id, result: response.resultObject())
        } catch {
            try await sendErrorResponse(id: id, code: -32000, message: error.localizedDescription)
        }
    }

    private func handleElicitationRequest(id: Any, params: [String: Any]) async throws {
        guard let elicitation = clientRequestHandlers.elicitation else {
            try await sendErrorResponse(
                id: id,
                code: -32000,
                message: "MCP elicitation is not supported by cerberus."
            )
            return
        }

        do {
            let request = MCPElicitationRequest(serverName: configuration.name, params: params)
            let response = try await elicitation(request)
            try await sendResultResponse(id: id, result: response.resultObject(for: request))
        } catch {
            try await sendErrorResponse(id: id, code: -32000, message: error.localizedDescription)
        }
    }

    private func sendResultResponse(id: Any, result: [String: Any]) async throws {
        _ = try await post([
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ], expectingResponseID: nil)
    }

    private func sendErrorResponse(id: Any, code: Int, message: String) async throws {
        _ = try await post([
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ], expectingResponseID: nil)
    }

    private func applyAuthorizationHeaders(to request: inout URLRequest) throws {
        if !configuration.headers.keys.contains(where: { $0.localizedCaseInsensitiveCompare("Authorization") == .orderedSame }),
           let accessToken = try Self.accessToken(for: configuration) {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        for (header, value) in configuration.headers {
            request.setValue(value, forHTTPHeaderField: header)
        }
    }

    private static func accessToken(for configuration: MCPServerConfiguration) throws -> String? {
        let account = configuration.accessTokenKeychainAccount ?? MCPOAuthKeychainAccount.accessToken(serverName: configuration.name)
        guard let data = try KeychainSecretStore(account: account).data(),
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private static func toolDescriptor(from object: [String: Any]) -> MCPToolDescriptor? {
        guard let name = object["name"] as? String else {
            return nil
        }

        return MCPToolDescriptor(
            name: name,
            title: object["title"] as? String,
            description: object["description"] as? String,
            inputSchemaJSON: stableJSONString(object["inputSchema"] ?? [:]),
            readOnlyHint: (object["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool
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
