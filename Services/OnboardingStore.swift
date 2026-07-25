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

@MainActor
final class OnboardingStore: ObservableObject {
  @Published private(set) var currentStep: OnboardingStep
  @Published private(set) var isComplete: Bool

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    isComplete = defaults.bool(forKey: Self.completedDefaultsKey)
    currentStep = .accessibility
  }

  var isActive: Bool { isComplete == false }
  var canGoBack: Bool { currentStep.rawValue > OnboardingStep.accessibility.rawValue }

  func advance() {
    guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
      complete()
      return
    }
    currentStep = next
  }

  func goBack() {
    guard let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
    currentStep = previous
  }

  func complete() {
    isComplete = true
    defaults.set(true, forKey: Self.completedDefaultsKey)
  }

  private static let completedDefaultsKey = "onboarding.completed"
}
