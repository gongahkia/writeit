import Combine
import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
  case accessibility
  case shortcut
  case delivery
  case recognition
  case cloudConsent
  case modelDownload

  var id: Int { rawValue }
  var title: String {
    switch self {
    case .accessibility: "Allow Accessibility"
    case .shortcut: "Choose a shortcut"
    case .delivery: "Choose delivery"
    case .recognition: "Choose recognition"
    case .cloudConsent: "Review cloud privacy"
    case .modelDownload: "Set up local recognition"
    }
  }
  var detail: String {
    switch self {
    case .accessibility: "WriteIt needs Accessibility permission to capture and insert text."
    case .shortcut: "Choose how you start and finish handwriting."
    case .delivery: "Review how recognized text reaches the focused app."
    case .recognition: "Choose a language and recognition backend."
    case .cloudConsent: "Cloud recognition stays off until you explicitly allow it."
    case .modelDownload: "Review local recognition availability before starting."
    }
  }
}

enum OnboardingRecognitionSelectionState: Equatable {
  case ready(RecognitionLanguageResolution)
  case unavailableBackend
  case unsupportedLanguage(RecognitionLanguage)

  init(
    backendID: String,
    language: RecognitionLanguage,
    backends: [RecognitionBackendCapabilities]
  ) {
    guard let backend = backends.first(where: { $0.identifier == backendID }) else {
      self = .unavailableBackend
      return
    }
    guard let resolution = backend.resolve(language) else {
      self = .unsupportedLanguage(language)
      return
    }
    self = .ready(resolution)
  }

  var allowsAdvance: Bool {
    if case .ready = self { return true }
    return false
  }

  var message: String {
    switch self {
    case .ready(let resolution) where resolution.usedFallback:
      "Selected backend uses English for \(resolution.requested.displayName)."
    case .ready:
      "Selected backend supports this language."
    case .unavailableBackend:
      "Choose an available recognition backend."
    case .unsupportedLanguage(let language):
      "Selected backend does not support \(language.displayName) or English fallback."
    }
  }
}

@MainActor
final class OnboardingStore: ObservableObject {
  @Published private(set) var currentStep: OnboardingStep
  @Published private(set) var isComplete: Bool
  @Published private(set) var hasAcknowledgedCloudPrivacy = false

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let isComplete = defaults.bool(forKey: Self.completedDefaultsKey)
    let savedStep = Self.savedStep(in: defaults)
    self.isComplete = isComplete
    currentStep = isComplete ? .accessibility : savedStep ?? .accessibility
    hasAcknowledgedCloudPrivacy =
      isComplete || savedStep == nil
      ? false
      : defaults.bool(forKey: Self.cloudPrivacyAcknowledgedDefaultsKey)
    if isComplete || savedStep == nil {
      defaults.removeObject(forKey: Self.currentStepDefaultsKey)
      defaults.removeObject(forKey: Self.cloudPrivacyAcknowledgedDefaultsKey)
    }
  }

  var isActive: Bool { isComplete == false }
  var canGoBack: Bool { currentStep.rawValue > OnboardingStep.accessibility.rawValue }
  var canAdvance: Bool {
    currentStep != .cloudConsent || hasAcknowledgedCloudPrivacy
  }

  func advance() {
    guard canAdvance else { return }
    guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
      complete()
      return
    }
    currentStep = next
    persistProgress()
  }

  func goBack() {
    guard let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
    currentStep = previous
    persistProgress()
  }

  func acknowledgeCloudPrivacy() {
    hasAcknowledgedCloudPrivacy = true
    persistProgress()
  }

  private func complete() {
    isComplete = true
    defaults.set(true, forKey: Self.completedDefaultsKey)
    clearProgress()
  }

  private static let completedDefaultsKey = "onboarding.completed"
  private static let currentStepDefaultsKey = "onboarding.currentStep"
  private static let cloudPrivacyAcknowledgedDefaultsKey = "onboarding.cloudPrivacyAcknowledged"

  private static func savedStep(in defaults: UserDefaults) -> OnboardingStep? {
    guard let rawValue = defaults.object(forKey: currentStepDefaultsKey) as? Int else { return nil }
    return OnboardingStep(rawValue: rawValue)
  }

  private func persistProgress() {
    defaults.set(currentStep.rawValue, forKey: Self.currentStepDefaultsKey)
    defaults.set(hasAcknowledgedCloudPrivacy, forKey: Self.cloudPrivacyAcknowledgedDefaultsKey)
  }

  private func clearProgress() {
    defaults.removeObject(forKey: Self.currentStepDefaultsKey)
    defaults.removeObject(forKey: Self.cloudPrivacyAcknowledgedDefaultsKey)
  }
}
