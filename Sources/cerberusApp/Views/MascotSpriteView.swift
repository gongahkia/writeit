import SwiftUI
import cerberusCore

struct MascotSpriteView: View {
    let state: AssistantState
    let tint: Color

    var body: some View {
        Image(nsImage: MascotSprite(state: state).image)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(tint)
            .scaledToFit()
            .accessibilityHidden(true)
    }
}
