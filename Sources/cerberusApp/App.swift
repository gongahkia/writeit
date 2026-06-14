import SwiftUI
import cerberusCore

@main
struct CerberusApp: App {
    @StateObject private var model = CerberusAppModel()

    var body: some Scene {
        MenuBarExtra("cerberus", systemImage: model.menuBarSystemImage) {
            StatusPanel(model: model)
                .frame(width: 340)
                .padding(14)
        }
        .menuBarExtraStyle(.window)
    }
}
