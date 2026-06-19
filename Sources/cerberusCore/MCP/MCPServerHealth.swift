import Foundation

public enum MCPServerHealthState: String, Codable, Equatable, Sendable {
    case configured
    case disabled
    case listening
    case handled
    case unsupported
    case error
}

public struct MCPServerHealthLine: Equatable, Identifiable, Sendable {
    public let name: String
    public let transport: MCPTransport
    public let state: MCPServerHealthState
    public let detail: String

    public var id: String {
        name
    }

    public init(name: String, transport: MCPTransport, state: MCPServerHealthState, detail: String) {
        self.name = name
        self.transport = transport
        self.state = state
        self.detail = detail
    }

    public var displayText: String {
        "\(name) (\(transport.rawValue)): \(detail)"
    }
}

public enum MCPServerHealthReporter {
    public static func lines(
        configurations: [MCPServerConfiguration],
        enabled: Bool,
        states: [String: MCPServerHealthState] = [:],
        details: [String: String] = [:]
    ) -> [MCPServerHealthLine] {
        configurations.sorted { $0.name < $1.name }.map { configuration in
            let state = enabled ? states[configuration.name, default: .configured] : .disabled
            return MCPServerHealthLine(
                name: configuration.name,
                transport: configuration.transport,
                state: state,
                detail: details[configuration.name] ?? defaultDetail(for: state, transport: configuration.transport)
            )
        }
    }

    private static func defaultDetail(for state: MCPServerHealthState, transport: MCPTransport) -> String {
        switch state {
        case .configured:
            transport == .streamableHTTP ? "configured" : "configured; no background listener"
        case .disabled:
            "disabled"
        case .listening:
            "listening"
        case .handled:
            "handled background request"
        case .unsupported:
            "GET SSE unavailable"
        case .error:
            "error"
        }
    }
}
