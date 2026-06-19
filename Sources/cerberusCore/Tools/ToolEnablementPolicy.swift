import Foundation

public struct ToolEnablementPolicy: Sendable {
    public let ambientAllowlist: ToolSessionAllowlist
    public let mcpEnabled: Bool
    public let shellEnabled: Bool

    public init(
        ambientAllowlist: ToolSessionAllowlist = ToolSessionAllowlist(),
        mcpEnabled: Bool = false,
        shellEnabled: Bool = false
    ) {
        self.ambientAllowlist = ambientAllowlist
        self.mcpEnabled = mcpEnabled
        self.shellEnabled = shellEnabled
    }

    public func enabledSummaries(
        ambientSummaries: [ToolSummary],
        mcpSummaries: [ToolSummary],
        shellSummary: ToolSummary
    ) -> [ToolSummary] {
        var summaries = ambientAllowlist.filter(ambientSummaries)
        if mcpEnabled {
            summaries += mcpSummaries
        }
        if shellEnabled {
            summaries.append(shellSummary)
        }
        return summaries.sorted { $0.name < $1.name }
    }
}
