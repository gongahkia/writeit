import SwiftUI

struct OnboardingView: View {
  @ObservedObject var onboarding: OnboardingStore
  @ObservedObject var capture: CaptureCoordinator
  @ObservedObject var preferences: Preferences
  @State private var shortcutValidationMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Welcome to WriteIt").font(.system(size: 30, weight: .bold))
      Text("Step \(onboarding.currentStep.rawValue + 1) of \(OnboardingStep.allCases.count)")
        .foregroundStyle(.secondary)
      ProgressView(
        value: Double(onboarding.currentStep.rawValue + 1),
        total: Double(OnboardingStep.allCases.count)
      )
      GroupBox(onboarding.currentStep.title) {
        VStack(alignment: .leading, spacing: 12) {
          Text(onboarding.currentStep.detail)
          if onboarding.currentStep == .accessibility {
            accessibilityStatus
          }
          if onboarding.currentStep == .shortcut {
            shortcutSetup
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
      }
      HStack {
        Button("Back", action: onboarding.goBack).disabled(onboarding.canGoBack == false)
        Spacer()
        Button(
          onboarding.currentStep == .modelDownload ? "Finish setup" : "Continue",
          action: onboarding.advance
        )
        .buttonStyle(.borderedProminent)
      }
    }
    .frame(minWidth: 520, minHeight: 320)
    .padding(32)
    .onAppear { capture.refreshAccessibility(force: true) }
    .onChange(of: onboarding.currentStep) { _, step in
      if step == .accessibility { capture.refreshAccessibility(force: true) }
    }
    .onChange(of: preferences.shortcut) { _, _ in capture.restartShortcutMonitor() }
  }

  @ViewBuilder
  private var accessibilityStatus: some View {
    Label(
      capture.accessibilityGranted ? "Accessibility enabled" : "Accessibility required",
      systemImage: capture.accessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
    )
    .foregroundStyle(capture.accessibilityGranted ? .green : .orange)
    if capture.accessibilityGranted == false {
      Text("After enabling it in System Settings, this updates automatically.")
        .foregroundStyle(.secondary)
      Button("Allow Accessibility", action: capture.requestAccessibility)
    }
  }

  @ViewBuilder
  private var shortcutSetup: some View {
    HStack {
      Text("Capture shortcut")
      Spacer()
      ShortcutRecorder(
        shortcut: $preferences.shortcut,
        validationMessage: $shortcutValidationMessage
      )
    }
    if let shortcutValidationMessage {
      Text(shortcutValidationMessage).font(.caption).foregroundStyle(.red)
    }
    Text("Press it once to start writing and again to submit.")
      .foregroundStyle(.secondary)
  }
}
