import AppKit
import Foundation
import Testing
@testable import cerberusApp
import cerberusCore

@Test(arguments: [
    (AssistantState.idle, MascotSprite.r1c1),
    (.listening, .r3c2),
    (.reasoning, .r3c1),
    (.awaitingConfirm, .r4c4),
    (.executing, .r2c3),
    (.speaking, .r4c2)
])
func mascotSpriteMatchesAssistantState(state: AssistantState, expected: MascotSprite) {
    #expect(MascotSprite(state: state) == expected)
}

@Test(arguments: MascotSprite.allCases)
func mascotSpriteResourceIsTransparent(sprite: MascotSprite) throws {
    let data = try Data(contentsOf: sprite.resourceURL)
    let representation = try #require(NSBitmapImageRep(data: data))
    #expect(representation.hasAlpha == true)
}

@Test(arguments: MascotSprite.allCases)
func mascotSpriteMenuBarImageIsTemplate(sprite: MascotSprite) {
    let image = sprite.menuBarImage

    #expect(image.size == MascotSprite.menuBarImageSize)
    #expect(image.isTemplate)
}
