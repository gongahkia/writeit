import Foundation

public struct ToolEnablementPolicy: Sendable {
    public let ambientAllowlist: ToolSessionAllowlist
    public let sessionDisabledToolNames: Set<String>
    public let mcpEnabled: Bool
    public let shellEnabled: Bool

    public init(
        ambientAllowlist: ToolSessionAllowlist = ToolSessionAllowlist(),
        sessionDisabledToolNames: Set<String> = [],
        mcpEnabled: Bool = false,
        shellEnabled: Bool = false
    ) {
        self.ambientAllowlist = ambientAllowlist
        self.sessionDisabledToolNames = sessionDisabledToolNames
        self.mcpEnabled = mcpEnabled
        self.shellEnabled = shellEnabled
    }

    public func enabledSummaries(
        ambientSummaries: [ToolSummary],
        mcpSummaries: [ToolSummary],
        shellSummary: ToolSummary
    ) -> [ToolSummary] {
        var summaries = ambientAllowlist.filter(ambientSummaries)
            .filter { !sessionDisabledToolNames.contains($0.name) }
        if mcpEnabled {
            summaries += mcpSummaries.filter { !sessionDisabledToolNames.contains($0.name) }
        }
        if shellEnabled {
            if !sessionDisabledToolNames.contains(shellSummary.name) {
                summaries.append(shellSummary)
            }
        }
        return summaries.sorted { $0.name < $1.name }
    }
}
