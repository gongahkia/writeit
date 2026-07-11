import AppKit
import SwiftUI
import cerberusCore

enum MascotSprite: String, CaseIterable {
    static let menuBarImageSize = NSSize(width: 30, height: 30)
    static let menuBarDrawingRect = NSRect(x: 1, y: 2, width: 28, height: 28)

    case r1c1
    case r1c2
    case r1c3
    case r1c4
    case r2c1
    case r2c2
    case r2c3
    case r2c4
    case r3c1
    case r3c2
    case r3c3
    case r3c4
    case r4c1
    case r4c2
    case r4c3
    case r4c4

    init(state: AssistantState) {
        switch state {
        case .idle:
            self = .r1c1
        case .listening:
            self = .r3c2
        case .reasoning:
            self = .r3c1
        case .awaitingConfirm:
            self = .r4c4
        case .executing:
            self = .r2c3
        case .speaking:
            self = .r4c2
        }
    }

    var resourceURL: URL {
        guard let url = Bundle.module.url(
            forResource: "mascot-\(rawValue)",
            withExtension: "png"
        ) else {
            preconditionFailure("Missing mascot resource: \(rawValue)")
        }
        return url
    }

    var image: NSImage {
        guard let image = NSImage(contentsOf: resourceURL) else {
            preconditionFailure("Unreadable mascot resource: \(rawValue)")
        }
        return image
    }

    var menuBarImage: NSImage {
        let result = NSImage(size: Self.menuBarImageSize)
        result.lockFocus()
        image.draw(in: Self.menuBarDrawingRect)
        result.unlockFocus()
        result.isTemplate = true
        return result
    }
}
