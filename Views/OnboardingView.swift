import SwiftUI

struct OnboardingView: View {
  @ObservedObject var onboarding: OnboardingStore

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
        Text(onboarding.currentStep.detail)
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
  }
}
