import SwiftUI

struct AppProfileBackendPanel: View {
  @ObservedObject var profiles: AppProfileStore
  @ObservedObject var cloudProviders: CloudOCRProviderStore
  let profileCreator: CurrentAppProfileCreator
  let registry: RecognitionBackendRegistry
  let globalBackendID: String
  @State private var feedback: String?

  var body: some View {
    GroupBox("App profiles") {
      VStack(alignment: .leading, spacing: 12) {
        Text("Profiles may override the global recognizer. Cloud choices require explicit consent for each app.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Button("Add current app profile", action: addCurrentProfile)
        if profiles.profiles.isEmpty {
          Text("No app profiles configured.").foregroundStyle(.secondary)
        } else {
          ForEach(profiles.profiles) { profile in
            AppProfileBackendRow(
              profile: profile,
              profiles: profiles,
              cloudProviders: cloudProviders,
              registry: registry,
              globalBackendID: globalBackendID
            )
          }
        }
        if let feedback {
          Text(feedback).font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding(6)
    }
  }

  private func addCurrentProfile() {
    do {
      let profile = try profileCreator.create()
      feedback = "Profile ready for \(profile.bundleIdentifier)."
    } catch {
      feedback = (error as? LocalizedError)?.errorDescription ?? "Profile could not be created."
    }
  }
}
