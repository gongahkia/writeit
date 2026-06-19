import Foundation

public enum CerberusSettingsKeys {
    public static let wakePhrase = "wakePhrase"
    public static let prefersSoundWakeWordClassifier = "prefersSoundWakeWordClassifier"
    public static let routesSpeechDirectlyToAirPods = "routesSpeechDirectlyToAirPods"
    public static let onboardingSkipped = "onboardingSkipped"
    public static let requiresConfirmationForAllTools = "requiresConfirmationForAllTools"
    public static let requiresLocalFoundationModels = "requiresLocalFoundationModels"
    public static let usesConfiguredAdapter = "usesConfiguredAdapter"
    public static let hotKeyConfigurationID = "hotKeyConfigurationID"
    public static let shellProposalMode = "shellProposalMode"
    public static let headNodThreshold = "headNodThreshold"
    public static let headShakeThreshold = "headShakeThreshold"
    public static let headGestureCooldownSeconds = "headGestureCooldownSeconds"
    public static let allowsMailBodySearch = "allowsMailBodySearch"

    public static let persistedKeys = [
        wakePhrase,
        prefersSoundWakeWordClassifier,
        routesSpeechDirectlyToAirPods,
        onboardingSkipped,
        requiresConfirmationForAllTools,
        requiresLocalFoundationModels,
        usesConfiguredAdapter,
        hotKeyConfigurationID,
        shellProposalMode,
        headNodThreshold,
        headShakeThreshold,
        headGestureCooldownSeconds,
        allowsMailBodySearch
    ]
}
