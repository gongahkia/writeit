import FoundationModels

public struct FoundationModelAvailabilityStatusProvider: Sendable {
    public let availability: @Sendable () -> SystemLanguageModel.Availability

    public init(availability: @escaping @Sendable () -> SystemLanguageModel.Availability = { SystemLanguageModel.default.availability }) {
        self.availability = availability
    }

    public func statusLine() -> String {
        Self.statusLine(for: availability())
    }

    public func fallbackText() -> String {
        Self.fallbackText(for: availability())
    }

    public func diagnosticText() -> String {
        Self.diagnosticText(for: availability())
    }

    public func isAvailable() -> Bool {
        Self.isAvailable(availability())
    }

    public static func isAvailable(_ availability: SystemLanguageModel.Availability) -> Bool {
        if case .available = availability {
            return true
        }
        return false
    }

    public static func statusLine(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            "Foundation Models available"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                "Foundation Models unavailable: device not eligible"
            case .appleIntelligenceNotEnabled:
                "Foundation Models unavailable: Apple Intelligence not enabled"
            case .modelNotReady:
                "Foundation Models unavailable: model not ready"
            @unknown default:
                "Foundation Models unavailable"
            }
        @unknown default:
            "Foundation Models status unknown"
        }
    }

    public static func fallbackText(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            "Foundation Models are available."
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                "Foundation Models are unavailable on this Mac."
            case .appleIntelligenceNotEnabled:
                "Apple Intelligence is not enabled. Turn it on in System Settings to use model planning."
            case .modelNotReady:
                "The local model is not ready yet. Finish the Apple Intelligence model download, then try again."
            @unknown default:
                "Foundation Models are unavailable. Check System Settings and try again."
            }
        @unknown default:
            "Foundation Models status is unknown. Check System Settings and try again."
        }
    }

    public static func diagnosticText(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            "Local model planning is ready."
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                "This Mac does not report Foundation Models eligibility; use an Apple Intelligence capable target Mac."
            case .appleIntelligenceNotEnabled:
                "Open System Settings and enable Apple Intelligence before running model planning."
            case .modelNotReady:
                "Keep the Mac online and unlocked until Apple Intelligence finishes downloading its local model."
            @unknown default:
                "Check Apple Intelligence state in System Settings, then refresh this status."
            }
        @unknown default:
            "Refresh after confirming Apple Intelligence state in System Settings."
        }
    }
}
