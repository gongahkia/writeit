import SwiftUI

struct AppProfileBackendRow: View {
  let profile: AppProfile
  @ObservedObject var profiles: AppProfileStore
  @ObservedObject var cloudProviders: CloudOCRProviderStore
  let registry: RecognitionBackendRegistry
  let globalBackendID: String
  @State private var backendID: String
  @State private var outputStrategy: OutputStrategy?
  @State private var feedback: String?
  @State private var showsRemovalConfirmation = false

  init(
    profile: AppProfile,
    profiles: AppProfileStore,
    cloudProviders: CloudOCRProviderStore,
    registry: RecognitionBackendRegistry,
    globalBackendID: String
  ) {
    self.profile = profile
    self.profiles = profiles
    self.cloudProviders = cloudProviders
    self.registry = registry
    self.globalBackendID = globalBackendID
    _backendID = State(initialValue: profile.overrides.recognitionBackendID ?? "")
    _outputStrategy = State(initialValue: profile.overrides.outputStrategy)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(profile.bundleIdentifier).font(.headline)
          Text(backendSummary).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Label(
          profile.isEnabled ? "Active" : "Disabled",
          systemImage: profile.isEnabled ? "checkmark.circle.fill" : "pause.circle"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(profile.isEnabled ? .green : .secondary)
        Button(profile.isEnabled ? "Disable" : "Enable", action: toggleEnabled)
          .buttonStyle(.bordered)
      }
      RecognitionBackendSelectionPicker(
        title: "Recognizer",
        selection: $backendID,
        backends: registry.availableBackends,
        includesGlobalDefault: true
      )
      .disabled(profile.isEnabled == false)
      .onChange(of: backendID) { _, newValue in setBackend(newValue) }
      .onChange(of: profile.overrides.recognitionBackendID) { _, newValue in
        backendID = newValue ?? ""
      }
      Picker("Output", selection: $outputStrategy) {
        Text("Use global default").tag(OutputStrategy?.none)
        ForEach(OutputStrategy.allCases) { strategy in
          Text(strategy.title).tag(OutputStrategy?.some(strategy))
        }
      }
      .disabled(profile.isEnabled == false)
      .accessibilityIdentifier("profile.outputStrategy")
      .onChange(of: outputStrategy) { _, newValue in setOutputStrategy(newValue) }
      .onChange(of: profile.overrides.outputStrategy) { _, newValue in outputStrategy = newValue }
      if requiresCloudConsent {
        Text(CloudOCRDisclosure.message).font(.caption).foregroundStyle(.secondary)
        Button(
          profile.overrides.cloudOCRConsent?.allowsCloudOCR == true
            ? "Revoke cloud OCR consent" : "Allow cloud OCR for this app",
          action: toggleConsent
        )
        .buttonStyle(.bordered)
        if profile.overrides.cloudOCRConsent?.allowsCloudOCR == false {
          Text("Cloud recognition will fail until consent is current.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      Text(AICleanupDisclosure.message).font(.caption).foregroundStyle(.secondary)
      Button(
        profile.overrides.aiCleanupConsent?.allowsAICleanup == true
          ? "Revoke AI cleanup consent" : "Allow AI cleanup for this app",
        action: toggleAICleanupConsent
      )
      .buttonStyle(.bordered)
      if profile.overrides.aiCleanupConsent?.allowsAICleanup == false {
        Text("AI cleanup will not send recognized text until consent is current.")
          .font(.caption).foregroundStyle(.secondary)
      }
      if let feedback {
        Text(feedback).font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        Button("Remove profile", role: .destructive, action: { showsRemovalConfirmation = true })
          .buttonStyle(.bordered)
      }
      .confirmationDialog(
        "Remove \(profile.bundleIdentifier)?",
        isPresented: $showsRemovalConfirmation,
        titleVisibility: .visible
      ) {
        Button("Remove profile", role: .destructive, action: removeProfile)
      } message: {
        Text("This removes only this app profile and its consent choices.")
      }
    }
    .padding(14)
    .background(
      WriteItTheme.cardFill,
      in: RoundedRectangle(cornerRadius: WriteItTheme.cardCornerRadius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: WriteItTheme.cardCornerRadius, style: .continuous).stroke(
        WriteItTheme.cardStroke)
    )
    .opacity(profile.isEnabled ? 1 : 0.72)
  }

  private var effectiveBackendID: String {
    backendID.isEmpty ? globalBackendID : backendID
  }

  private var requiresCloudConsent: Bool {
    CloudOCRProvider(rawValue: effectiveBackendID) != nil
  }

  private var backendSummary: String {
    backendID.isEmpty ? "Using global recognizer" : "Overrides recognizer: \(backendID)"
  }

  private func toggleEnabled() {
    do {
      try profiles.setEnabled(profile.isEnabled == false, for: profile.id)
    } catch {
      feedback = (error as? LocalizedError)?.errorDescription ?? "Profile could not be updated."
    }
  }

  private func setBackend(_ backendID: String) {
    do {
      try profiles.setRecognitionBackendID(backendID.isEmpty ? nil : backendID, for: profile.id)
    } catch {
      feedback = (error as? LocalizedError)?.errorDescription ?? "Profile could not be updated."
    }
  }

  private func setOutputStrategy(_ outputStrategy: OutputStrategy?) {
    do {
      try profiles.setOutputStrategy(outputStrategy, for: profile.id)
    } catch {
      feedback = (error as? LocalizedError)?.errorDescription ?? "Profile could not be updated."
    }
  }

  private func toggleConsent() {
    do {
      let consent = profile.overrides.cloudOCRConsent?.allowsCloudOCR == true
        ? nil : CloudOCRConsent()
      try profiles.setCloudOCRConsent(consent, for: profile.id)
    } catch {
      feedback = (error as? LocalizedError)?.errorDescription ?? "Cloud consent could not be updated."
    }
  }

  private func toggleAICleanupConsent() {
    do {
      let consent = profile.overrides.aiCleanupConsent?.allowsAICleanup == true
        ? nil : AICleanupConsent()
      try profiles.setAICleanupConsent(consent, for: profile.id)
    } catch {
      feedback = (error as? LocalizedError)?.errorDescription ?? "AI cleanup consent could not be updated."
    }
  }

  private func removeProfile() {
    do {
      try profiles.remove(profile.id)
    } catch {
      feedback = (error as? LocalizedError)?.errorDescription ?? "Profile could not be removed."
    }
  }
}
