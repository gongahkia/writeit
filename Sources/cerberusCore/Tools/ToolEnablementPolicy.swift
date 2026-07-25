import Foundation

public struct ToolEnablementPolicy: Sendable {
    public let ambientAllowlist: ToolSessionAllowlist
    public let sessionDisabledToolNames: Set<String>

    public init(
        ambientAllowlist: ToolSessionAllowlist = ToolSessionAllowlist(),
        sessionDisabledToolNames: Set<String> = []
    ) {
        self.ambientAllowlist = ambientAllowlist
        self.sessionDisabledToolNames = sessionDisabledToolNames
    }

    public func enabledSummaries(
        ambientSummaries: [ToolSummary]
    ) -> [ToolSummary] {
        let summaries = ambientAllowlist.filter(ambientSummaries)
            .filter { !sessionDisabledToolNames.contains($0.name) }
        return summaries.sorted { $0.name < $1.name }
    }
}
