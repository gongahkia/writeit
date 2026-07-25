import SwiftUI

struct RecognitionBackendSelectionPicker: View {
  let title: String
  @Binding var selection: String
  let backends: [RecognitionBackendCapabilities]
  var includesGlobalDefault = false

  var body: some View {
    Picker(title, selection: $selection) {
      if includesGlobalDefault {
        Text("Use global default").tag("")
      }
      if isUnavailableSelection {
        Text("Unavailable: \(selection)").tag(selection)
      }
      ForEach(backends, id: \.identifier) { backend in
        Text(backend.displayName).tag(backend.identifier)
      }
    }
  }

  private var isUnavailableSelection: Bool {
    selection.isEmpty == false && backends.contains(where: { $0.identifier == selection }) == false
  }
}
