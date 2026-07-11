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
        .commands {
            CommandMenu("Cerberus") {
                Button("Listen") {
                    model.startListening()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Cancel") {
                    model.cancel()
                }
                .keyboardShortcut(".", modifiers: [.command])

                Button("Refresh Permissions") {
                    model.refreshPermissions()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Open Settings") {
                    model.selectedPanelSection = .settings
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}

private struct MenuBarStatusIcon: View {
    @ObservedObject var model: CerberusAppModel

    var body: some View {
        Label {
            Text("cerberus")
        } icon: {
            MascotSpriteView(
                state: model.state,
                tint: model.menuBarStatusTint == .red ? .red : .primary
            )
                .frame(width: 14, height: 14)
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("cerberus \(model.state.displayName)")
    }
}
