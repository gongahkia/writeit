import Foundation

public struct MCPSamplingRequest: Equatable, Sendable {
    public let serverName: String
    public let messagesText: String
    public let systemPrompt: String?
    public let maxTokens: Int?
    public let rawParamsJSON: String

    init(serverName: String, params: [String: Any]) {
        self.serverName = serverName
        messagesText = (params["messages"] as? [[String: Any]] ?? [])
            .map(Self.messageText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        systemPrompt = params["systemPrompt"] as? String
        maxTokens = Self.integer(params["maxTokens"])
        rawParamsJSON = Self.stableJSONString(params)
    }

    private static func messageText(_ object: [String: Any]) -> String {
        let role = object["role"] as? String ?? "message"
        guard let content = object["content"] as? [String: Any] else {
            return "[\(role)] \(stableJSONString(object))"
        }
        let text = contentText(content)
        return text.isEmpty ? "" : "[\(role)] \(text)"
    }

    private static func contentText(_ object: [String: Any]) -> String {
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
        default:
            return stableJSONString(object)
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
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

public struct MCPSamplingResponse: Equatable, Sendable {
    public let text: String
    public let model: String
    public let stopReason: String

    public init(text: String, model: String = "cerberus", stopReason: String = "endTurn") {
        self.text = text
        self.model = model
        self.stopReason = stopReason
    }

    func resultObject() throws -> [String: Any] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP sampling response text cannot be empty.")
        }
        return [
            "role": "assistant",
            "content": [
                "type": "text",
                "text": trimmedText
            ],
            "model": model,
            "stopReason": stopReason
        ]
    }
}

public struct MCPElicitationRequest: Equatable, Sendable {
    public let serverName: String
    public let message: String
    public let schemaJSON: String
    public let rawParamsJSON: String

    init(serverName: String, params: [String: Any]) {
        self.serverName = serverName
        message = params["message"] as? String ?? ""
        let schema = params["requestedSchema"] ?? [:]
        schemaJSON = Self.stableJSONString(schema)
        rawParamsJSON = Self.stableJSONString(params)
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

public enum MCPElicitationAction: String, Sendable {
    case accept
    case decline
    case cancel
}

public struct MCPElicitationResponse: Equatable, Sendable {
    public let action: MCPElicitationAction
    public let contentJSON: String

    public init(action: MCPElicitationAction, contentJSON: String = "{}") {
        self.action = action
        self.contentJSON = contentJSON
    }

    func resultObject(for request: MCPElicitationRequest) throws -> [String: Any] {
        guard action == .accept else {
            return ["action": action.rawValue]
        }

        let content = try Self.jsonObject(from: contentJSON, errorMessage: "MCP elicitation content must be a JSON object.")
        let schema = try Self.jsonObject(from: request.schemaJSON, errorMessage: "MCP elicitation schema must be a JSON object.")
        try Self.validate(content: content, against: schema)
        return [
            "action": action.rawValue,
            "content": content
        ]
    }

    private static func validate(content: [String: Any], against schema: [String: Any]) throws {
        guard schema["type"] as? String == "object" else {
            throw ToolExecutionError.invalidArguments("MCP elicitation schema must be a flat object.")
        }

        let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
        let required = Set(schema["required"] as? [String] ?? [])

        for key in required where content[key] == nil {
            throw ToolExecutionError.invalidArguments("MCP elicitation content is missing required field: \(key)")
        }

        for (key, value) in content {
            guard let property = properties[key] else {
                throw ToolExecutionError.invalidArguments("MCP elicitation content contains an unknown field: \(key)")
            }
            try validate(value: value, key: key, property: property)
        }
    }

    private static func validate(value: Any, key: String, property: [String: Any]) throws {
        let type = property["type"] as? String ?? "string"
        switch type {
        case "string":
            guard let string = value as? String else {
                throw ToolExecutionError.invalidArguments("MCP elicitation field must be a string: \(key)")
            }
            if let minLength = integer(property["minLength"]), string.count < minLength {
                throw ToolExecutionError.invalidArguments("MCP elicitation field is too short: \(key)")
            }
            if let maxLength = integer(property["maxLength"]), string.count > maxLength {
                throw ToolExecutionError.invalidArguments("MCP elicitation field is too long: \(key)")
            }
            if let values = property["enum"] as? [String], !values.contains(string) {
                throw ToolExecutionError.invalidArguments("MCP elicitation field is not an allowed enum value: \(key)")
            }
        case "boolean":
            guard value is Bool else {
                throw ToolExecutionError.invalidArguments("MCP elicitation field must be a boolean: \(key)")
            }
        case "number", "integer":
            guard let numericValue = number(value), !isBoolNumber(value) else {
                throw ToolExecutionError.invalidArguments("MCP elicitation field must be a number: \(key)")
            }
            if type == "integer", numericValue.rounded() != numericValue {
                throw ToolExecutionError.invalidArguments("MCP elicitation field must be an integer: \(key)")
            }
            if let minimum = number(property["minimum"]), numericValue < minimum {
                throw ToolExecutionError.invalidArguments("MCP elicitation field is below minimum: \(key)")
            }
            if let maximum = number(property["maximum"]), numericValue > maximum {
                throw ToolExecutionError.invalidArguments("MCP elicitation field is above maximum: \(key)")
            }
        default:
            throw ToolExecutionError.invalidArguments("MCP elicitation field has unsupported type: \(key)")
        }
    }

    private static func jsonObject(from string: String, errorMessage: String) throws -> [String: Any] {
        let data = Data(string.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let object = object as? [String: Any],
              JSONSerialization.isValidJSONObject(object) else {
            throw ToolExecutionError.invalidArguments(errorMessage)
        }
        return object
    }

    private static func integer(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber, !isBoolNumber(number) {
            return number.intValue
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let number = value as? NSNumber, !isBoolNumber(number) {
            return number.doubleValue
        }
        return nil
    }

    private static func isBoolNumber(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else {
            return false
        }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}

public struct MCPClientRequestHandlers: Sendable {
    public typealias SamplingHandler = @Sendable (MCPSamplingRequest) async throws -> MCPSamplingResponse
    public typealias ElicitationHandler = @Sendable (MCPElicitationRequest) async throws -> MCPElicitationResponse

    public let sampling: SamplingHandler?
    public let elicitation: ElicitationHandler?

    public init(sampling: SamplingHandler? = nil, elicitation: ElicitationHandler? = nil) {
        self.sampling = sampling
        self.elicitation = elicitation
    }

    public static let none = MCPClientRequestHandlers()

    var capabilities: [String: Any] {
        var object: [String: Any] = [:]
        if sampling != nil {
            object["sampling"] = [:]
        }
        if elicitation != nil {
            object["elicitation"] = [:]
        }
        return object
    }
}
