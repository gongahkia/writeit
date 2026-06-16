import SwiftUI
import cerberusCore

@main
struct CerberusApp: App {
    @StateObject private var model = CerberusAppModel()

    var body: some Scene {
        MenuBarExtra {
            StatusPanel(model: model)
                .frame(width: 340)
                .padding(14)
        } label: {
            MenuBarStatusIcon(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarStatusIcon: View {
    @ObservedObject var model: CerberusAppModel

    var body: some View {
        Label {
            Text("cerberus")
        } icon: {
            Image(systemName: model.menuBarSystemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(model.isMicrophoneActive ? .red : .primary)
        }
        .accessibilityLabel("cerberus \(model.state.displayName)")
    }
}
