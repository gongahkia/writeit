import Foundation

public enum MCPHTTPListenerPolicy {
    public static func listenerConfigurations(from configurations: [MCPServerConfiguration]) -> [MCPServerConfiguration] {
        configurations.filter { $0.transport == .streamableHTTP }
    }
}
