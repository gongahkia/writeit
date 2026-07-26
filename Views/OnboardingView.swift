import SwiftUI

struct OnboardingView: View {
  @ObservedObject var onboarding: OnboardingStore
  @ObservedObject var capture: CaptureCoordinator
  @ObservedObject var preferences: Preferences
  @ObservedObject var models: ModelStore
  @ObservedObject var customModelSource: CustomHTTPSModelSourceStore
  let recognitionRegistry: RecognitionBackendRegistry
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
          if onboarding.currentStep == .delivery {
            deliverySetup
          }
          if onboarding.currentStep == .recognition {
            recognitionSetup
          }
          if onboarding.currentStep == .cloudConsent {
            cloudPrivacySetup
          }
          if onboarding.currentStep == .modelDownload {
            modelDownloadSetup
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
        .disabled(canContinue == false)
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

  @ViewBuilder
  private var deliverySetup: some View {
    Picker("Delivery", selection: $preferences.outputStrategy) {
      ForEach(OutputStrategy.allCases) { Text($0.title).tag($0) }
    }
    Button("Copy delivery test", action: capture.runClipboardDeliveryTest)
    if let outcome = capture.deliveryTestOutcome {
      Label(
        outcome.message,
        systemImage: outcome.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
      )
      .foregroundStyle(outcome.failed ? .orange : .green)
    }
    Text("This copies a fixed test phrase without retaining history. Direct delivery is tested during capture.")
      .foregroundStyle(.secondary)
  }

  @ViewBuilder
  private var recognitionSetup: some View {
    Picker("Recognition language", selection: $preferences.recognitionLanguage) {
      ForEach(RecognitionLanguage.allCases) { Text($0.displayName).tag($0) }
    }
    RecognitionBackendSelectionPicker(
      title: "Recognition backend",
      selection: $preferences.recognitionBackendID,
      backends: recognitionRegistry.availableBackends
    )
    Label(
      recognitionSelection.message,
      systemImage: recognitionSelection.allowsAdvance ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    )
    .foregroundStyle(recognitionSelection.allowsAdvance ? .green : .orange)
  }

  private var recognitionSelection: OnboardingRecognitionSelectionState {
    OnboardingRecognitionSelectionState(
      backendID: preferences.recognitionBackendID,
      language: preferences.recognitionLanguage,
      backends: recognitionRegistry.availableBackends
    )
  }

  private var canContinue: Bool {
    onboarding.canAdvance && (
      onboarding.currentStep != .recognition || recognitionSelection.allowsAdvance
    ) && (onboarding.currentStep != .modelDownload || customModelSource.manifestURL.isEmpty || customModelSource.manifest != nil)
  }

  @ViewBuilder
  private var cloudPrivacySetup: some View {
    Text(CloudOCRDisclosure.message)
    Text(AICleanupDisclosure.message)
    Text("Both stay off until you explicitly allow them for an individual app profile.")
      .foregroundStyle(.secondary)
    Button(
      onboarding.hasAcknowledgedCloudPrivacy ? "Cloud privacy reviewed" : "I understand",
      action: onboarding.acknowledgeCloudPrivacy
    )
    .disabled(onboarding.hasAcknowledgedCloudPrivacy)
  }

  @ViewBuilder
  private var modelDownloadSetup: some View {
    TextField(
      "HTTPS model manifest URL",
      text: Binding(
        get: { customModelSource.manifestURL },
        set: { customModelSource.setManifestURL($0) }
      )
    )
    .textContentType(.URL)
    HStack {
      Button("Check source") { Task { await customModelSource.refresh() } }
        .disabled(customModelSource.manifestURL.isEmpty || customModelSource.isLoading)
      if customModelSource.isLoading { ProgressView().controlSize(.small) }
    }
    if let message = customModelSource.message {
      Text(message).font(.caption).foregroundStyle(.secondary)
    }
    ForEach(customModelSource.models) { manifest in
      HStack {
        VStack(alignment: .leading) {
          Text("\(manifest.id) \(manifest.version)")
          Text("\(manifest.assetSizeBytes.formatted(.byteCount(style: .file))) · \(manifest.license)")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Install") { Task { await customModelSource.download(manifest, into: models) } }
          .disabled(ModelCompatibilityChecker.failure(
            for: manifest, environment: ModelCompatibilityChecker.currentEnvironment(storageURL: ModelStore.defaultModelsDirectory)
          ) != nil)
      }
    }
    Text("Leave this blank to use Apple Vision. Custom models download only from the HTTPS URL you enter.")
      .font(.caption).foregroundStyle(.secondary)
  }
}
