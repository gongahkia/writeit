import Foundation
import FoundationModels

public struct MCPDynamicNativeToolAdapter: FoundationModels.Tool {
    public typealias Arguments = GeneratedContent
    public typealias Output = String

    private let serverName: String
    private let descriptor: MCPToolDescriptor
    private let runner: any MCPToolRunning
    private let auditLog: AuditLog?
    public let parameters: GenerationSchema

    public init(
        serverName: String,
        descriptor: MCPToolDescriptor,
        runner: any MCPToolRunning,
        auditLog: AuditLog? = nil
    ) throws {
        self.serverName = serverName
        self.descriptor = descriptor
        self.runner = runner
        self.auditLog = auditLog
        parameters = try MCPDynamicNativeToolSchema.parameters(for: descriptor, serverName: serverName)
    }

    public var name: String {
        "mcp.\(Self.sanitizeIdentifier(serverName)).\(Self.sanitizeIdentifier(descriptor.name))"
    }

    public var description: String {
        let text = descriptor.description ?? descriptor.title ?? "Call read-only MCP tool \(descriptor.name)."
        return "\(text) Server: \(serverName). Original tool: \(descriptor.name)."
    }

    public var includesSchemaInInstructions: Bool {
        true
    }

    public func call(arguments: GeneratedContent) async throws -> String {
        let result = try await runner.call(
            serverName: serverName,
            toolName: descriptor.name,
            argumentsJSON: arguments.jsonString
        )
        if let auditLog {
            _ = try? await auditLog.append(
                toolName: name,
                argumentsSummary: "\(serverName).\(descriptor.name) \(arguments.jsonString)",
                resultSummary: result.isError ? "MCP tool returned an error." : "MCP tool completed."
            )
        }
        let payload = result.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else {
            return result.isError ? "MCP tool returned an error." : "MCP tool completed."
        }
        return """
        Summary: \(result.isError ? "MCP tool returned an error." : "MCP tool completed.")
        Untrusted MCP tool output:
        <tool-output>
        \(payload)
        </tool-output>
        """
    }

    private static func sanitizeIdentifier(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }
        let identifier = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return identifier.isEmpty ? "tool" : identifier
    }
}

public enum MCPDynamicNativeToolSchema {
    public static func parameters(for descriptor: MCPToolDescriptor, serverName: String) throws -> GenerationSchema {
        guard let data = descriptor.inputSchemaJSON.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolExecutionError.invalidArguments("MCP tool inputSchema must be a JSON object.")
        }

        let root = try objectSchema(
            name: "MCP_\(sanitizeSchemaName(serverName))_\(sanitizeSchemaName(descriptor.name))",
            description: descriptor.description,
            object: object
        )
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func objectSchema(
        name: String,
        description: String?,
        object: [String: Any]
    ) throws -> DynamicGenerationSchema {
        if let type = object["type"], !schemaTypes(from: type).contains("object") {
            throw ToolExecutionError.invalidArguments("MCP native tool schemas must be flat JSON objects.")
        }

        let properties = object["properties"] as? [String: Any] ?? [:]
        let required = Set(object["required"] as? [String] ?? [])
        let dynamicProperties = try properties.keys.sorted().map { propertyName in
            guard let propertyObject = properties[propertyName] as? [String: Any] else {
                throw ToolExecutionError.invalidArguments("MCP property schema must be a JSON object: \(propertyName)")
            }
            return DynamicGenerationSchema.Property(
                name: propertyName,
                description: propertyObject["description"] as? String,
                schema: try primitiveSchema(name: propertyName, object: propertyObject),
                isOptional: !required.contains(propertyName)
            )
        }

        return DynamicGenerationSchema(name: name, description: description, properties: dynamicProperties)
    }

    private static func primitiveSchema(name: String, object: [String: Any]) throws -> DynamicGenerationSchema {
        let schemaName = sanitizeSchemaName(name)
        if let enumValues = object["enum"] as? [String], !enumValues.isEmpty {
            return DynamicGenerationSchema(name: schemaName, description: object["description"] as? String, anyOf: enumValues)
        }

        let types = schemaTypes(from: object["type"]).filter { $0 != "null" }
        guard let type = types.first, types.count == 1 else {
            throw ToolExecutionError.invalidArguments("MCP native tool property must declare one primitive type: \(name)")
        }

        switch type {
        case "string":
            return DynamicGenerationSchema(type: String.self)
        case "number":
            return DynamicGenerationSchema(type: Double.self)
        case "integer":
            return DynamicGenerationSchema(type: Int.self)
        case "boolean":
            return DynamicGenerationSchema(type: Bool.self)
        default:
            throw ToolExecutionError.invalidArguments("Unsupported MCP native tool property type: \(type)")
        }
    }

    private static func schemaTypes(from value: Any?) -> [String] {
        if let type = value as? String {
            return [type]
        }
        return value as? [String] ?? []
    }

    private static func sanitizeSchemaName(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }
        let name = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return name.isEmpty ? "Schema" : name
    }
}

public struct MCPNativeToolLoader: Sendable {
    private let registry: MCPServerRegistry
    private let clientRequestHandlers: MCPClientRequestHandlers
    private let auditLog: AuditLog?

    public init(
        registry: MCPServerRegistry = MCPServerRegistry(),
        clientRequestHandlers: MCPClientRequestHandlers = .none,
        auditLog: AuditLog? = nil
    ) {
        self.registry = registry
        self.clientRequestHandlers = clientRequestHandlers
        self.auditLog = auditLog
    }

    public func load() async throws -> [any FoundationModels.Tool] {
        let configurations = try await registry.configurations()
        var nativeTools: [any FoundationModels.Tool] = []

        for configuration in configurations where !configuration.nativeReadOnlyTools.isEmpty {
            let allowedToolNames = Set(configuration.nativeReadOnlyTools)
            let descriptors = try await listTools(for: configuration)
            for descriptor in descriptors where allowedToolNames.contains(descriptor.name) {
                if let tool = try? MCPDynamicNativeToolAdapter(
                    serverName: configuration.name,
                    descriptor: descriptor,
                    runner: MCPConfiguredToolRunner(registry: registry, clientRequestHandlers: clientRequestHandlers),
                    auditLog: auditLog
                ) {
                    nativeTools.append(tool)
                }
            }
        }

        return nativeTools
    }

    private func listTools(for configuration: MCPServerConfiguration) async throws -> [MCPToolDescriptor] {
        switch configuration.transport {
        case .stdio:
            return try await MCPStdioClient(
                configuration: configuration,
                clientRequestHandlers: clientRequestHandlers
            ).listTools()
        case .streamableHTTP:
            return try await MCPStreamableHTTPClient(
                configuration: configuration,
                clientRequestHandlers: clientRequestHandlers
            ).listTools()
        }
    }
}
