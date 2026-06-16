import Foundation

public struct MCPServerConfiguration: Codable, Equatable, Sendable {
    public let name: String
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?

    public init(name: String, executable: String, arguments: [String] = [], workingDirectory: String? = nil) {
        self.name = name
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
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
