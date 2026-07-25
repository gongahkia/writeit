import Foundation

public struct ToolProfileConfiguration: Equatable, Sendable {
    public let disabledAmbientToolNames: Set<String>
    public let requiresConfirmationForAllTools: Bool

    public init(
        disabledAmbientToolNames: Set<String>,
        requiresConfirmationForAllTools: Bool
    ) {
        self.disabledAmbientToolNames = disabledAmbientToolNames
        self.requiresConfirmationForAllTools = requiresConfirmationForAllTools
    }
}

public enum ToolProfile: String, CaseIterable, Identifiable, Sendable {
    case visionOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .visionOnly:
            "Vision only"
        }
    }

    public func configuration(ambientSummaries: [ToolSummary]) -> ToolProfileConfiguration {
        switch self {
        case .visionOnly:
            ToolProfileConfiguration(
                disabledAmbientToolNames: [],
                requiresConfirmationForAllTools: false
            )
        }
    }

    public static func profile(id: String) -> ToolProfile {
        ToolProfile(rawValue: id) ?? .visionOnly
    }
}
