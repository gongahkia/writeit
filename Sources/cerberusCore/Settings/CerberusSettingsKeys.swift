import Foundation

public enum CerberusSettingsKeys {
    public static let wakePhrase = "wakePhrase"
    public static let prefersSoundWakeWordClassifier = "prefersSoundWakeWordClassifier"
    public static let routesSpeechDirectlyToAirPods = "routesSpeechDirectlyToAirPods"
    public static let onboardingSkipped = "onboardingSkipped"
    public static let requiresConfirmationForAllTools = "requiresConfirmationForAllTools"
    public static let usesConfiguredAdapter = "usesConfiguredAdapter"
    public static let hotKeyConfigurationID = "hotKeyConfigurationID"

    public static let persistedKeys = [
        wakePhrase,
        prefersSoundWakeWordClassifier,
        routesSpeechDirectlyToAirPods,
        onboardingSkipped,
        requiresConfirmationForAllTools,
        usesConfiguredAdapter,
        hotKeyConfigurationID
    ]
}
