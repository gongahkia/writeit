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
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Profiles override recognition and privacy choices for one app.")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("\(profiles.profiles.filter(\.isEnabled).count) active of \(profiles.profiles.count)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Add current app profile", systemImage: "plus", action: addCurrentProfile)
            .buttonStyle(.bordered)
        }
        if profiles.profiles.isEmpty {
          ContentUnavailableView(
            "No app profiles",
            systemImage: "rectangle.stack.badge.plus",
            description: Text("Add the foreground app to customize its recognizer and consent."))
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
