import Foundation

public enum MCPTransport: String, Codable, Sendable {
    case stdio
    case streamableHTTP = "streamable_http"
}

public struct MCPServerConfiguration: Codable, Equatable, Sendable {
    public let name: String
    public let transport: MCPTransport
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?
    public let endpointURL: URL?
    public let headers: [String: String]

    public init(
        name: String,
        transport: MCPTransport = .stdio,
        executable: String = "",
        arguments: [String] = [],
        workingDirectory: String? = nil,
        endpointURL: URL? = nil,
        headers: [String: String] = [:]
    ) {
        self.name = name
        self.transport = transport
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.endpointURL = endpointURL
        self.headers = headers
    }

    enum CodingKeys: String, CodingKey {
        case name
        case transport
        case executable
        case arguments
        case workingDirectory
        case endpointURL
        case headers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        transport = try container.decodeIfPresent(MCPTransport.self, forKey: .transport) ?? .stdio
        executable = try container.decodeIfPresent(String.self, forKey: .executable) ?? ""
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        endpointURL = try container.decodeIfPresent(URL.self, forKey: .endpointURL)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(transport, forKey: .transport)
        try container.encode(executable, forKey: .executable)
        try container.encode(arguments, forKey: .arguments)
        try container.encodeIfPresent(workingDirectory, forKey: .workingDirectory)
        try container.encodeIfPresent(endpointURL, forKey: .endpointURL)
        try container.encode(headers, forKey: .headers)
    }
}

public struct MCPConfigurationFile: Codable, Equatable, Sendable {
    public let servers: [MCPServerConfiguration]

    public init(servers: [MCPServerConfiguration]) {
        self.servers = servers
    }
}

public actor MCPServerRegistry {
    private let fileURL: URL
    private var cachedConfigurations: [String: MCPServerConfiguration]?

    public init(fileURL: URL = MCPServerRegistry.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func configuration(named name: String) throws -> MCPServerConfiguration {
        if cachedConfigurations == nil {
            cachedConfigurations = try loadConfigurations()
        }

        guard let configuration = cachedConfigurations?[name] else {
            throw ToolExecutionError.denied("MCP server is not configured: \(name)")
        }

        return configuration
    }

    public func reload() {
        cachedConfigurations = nil
    }

    public static func defaultFileURL() -> URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cerberus", isDirectory: true)
        return supportDirectory.appendingPathComponent("mcp-servers.json")
    }

    private func loadConfigurations() throws -> [String: MCPServerConfiguration] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        let configurationFile = try JSONDecoder().decode(MCPConfigurationFile.self, from: data)
        var configurations: [String: MCPServerConfiguration] = [:]

        for server in configurationFile.servers {
            let name = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw ToolExecutionError.invalidArguments("MCP server name cannot be empty.")
            }
            guard configurations[name] == nil else {
                throw ToolExecutionError.invalidArguments("Duplicate MCP server name: \(name)")
            }
            configurations[name] = server
        }

        return configurations
    }
}
