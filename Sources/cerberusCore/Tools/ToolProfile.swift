import Foundation

public struct ToolProfileConfiguration: Equatable, Sendable {
    public let disabledAmbientToolNames: Set<String>
    public let mcpEnabled: Bool
    public let shellEnabled: Bool
    public let requiresConfirmationForAllTools: Bool

    public init(
        disabledAmbientToolNames: Set<String>,
        mcpEnabled: Bool,
        shellEnabled: Bool,
        requiresConfirmationForAllTools: Bool
    ) {
        self.disabledAmbientToolNames = disabledAmbientToolNames
        self.mcpEnabled = mcpEnabled
        self.shellEnabled = shellEnabled
        self.requiresConfirmationForAllTools = requiresConfirmationForAllTools
    }
}

public enum ToolProfile: String, CaseIterable, Identifiable, Sendable {
    case ambient
    case trustedDesk
    case explicitOperator

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ambient:
            "Ambient"
        case .trustedDesk:
            "Trusted desk"
        case .explicitOperator:
            "Explicit operator"
        }
    }

    public func configuration(ambientSummaries: [ToolSummary]) -> ToolProfileConfiguration {
        switch self {
        case .ambient:
            ToolProfileConfiguration(
                disabledAmbientToolNames: Set(ambientSummaries.filter(\.mutatesState).map(\.name)),
                mcpEnabled: false,
                shellEnabled: false,
                requiresConfirmationForAllTools: false
            )
        case .trustedDesk:
            ToolProfileConfiguration(
                disabledAmbientToolNames: [],
                mcpEnabled: false,
                shellEnabled: false,
                requiresConfirmationForAllTools: false
            )
        case .explicitOperator:
            ToolProfileConfiguration(
                disabledAmbientToolNames: [],
                mcpEnabled: true,
                shellEnabled: true,
                requiresConfirmationForAllTools: true
            )
        }
    }

    public static func profile(id: String) -> ToolProfile {
        ToolProfile(rawValue: id) ?? .trustedDesk
    }
}
