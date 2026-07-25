import Foundation

public struct ToolSessionAllowlist: Equatable, Sendable {
    public private(set) var disabledToolNames: Set<String>

    public init(disabledToolNames: Set<String> = []) {
        self.disabledToolNames = disabledToolNames
    }

    public func isEnabled(_ toolName: String) -> Bool {
        !disabledToolNames.contains(toolName)
    }

    public mutating func setEnabled(_ toolName: String, enabled: Bool) {
        if enabled {
            disabledToolNames.remove(toolName)
        } else {
            disabledToolNames.insert(toolName)
        }
    }

    public mutating func reset() {
        disabledToolNames.removeAll()
    }

    public func filter(_ summaries: [ToolSummary]) -> [ToolSummary] {
        summaries.filter { isEnabled($0.name) }
    }
}
