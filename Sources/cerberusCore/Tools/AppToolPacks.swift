import Foundation

public struct AppToolPack: Equatable, Sendable {
    public let appName: String
    public let aliases: [String]
    public let toolNames: [String]
    public let guidance: String

    public init(appName: String, aliases: [String], toolNames: [String], guidance: String) {
        self.appName = appName
        self.aliases = aliases
        self.toolNames = toolNames
        self.guidance = guidance
    }
}

public enum AppToolPacks {
    public static let all: [AppToolPack] = [
        AppToolPack(
            appName: "Xcode",
            aliases: ["xcode"],
            toolNames: ["screen.ocr", "screen.ui_elements", "screen.snapshot"],
            guidance: "Use screen reads only; never operate Xcode."
        ),
        AppToolPack(
            appName: "Terminal",
            aliases: ["terminal", "iterm"],
            toolNames: ["screen.ocr", "screen.ui_elements", "screen.snapshot"],
            guidance: "Use screen reads only; never run commands."
        ),
        AppToolPack(
            appName: "Safari",
            aliases: ["safari"],
            toolNames: ["screen.ocr", "screen.ui_elements", "screen.snapshot"],
            guidance: "Use screen reads only; never navigate or click."
        ),
        AppToolPack(
            appName: "Chrome",
            aliases: ["chrome", "google chrome"],
            toolNames: ["screen.ocr", "screen.ui_elements", "screen.snapshot"],
            guidance: "Use screen reads only; never navigate or click."
        ),
        AppToolPack(
            appName: "Calendar",
            aliases: ["calendar"],
            toolNames: ["screen.ocr", "screen.ui_elements", "screen.snapshot"],
            guidance: "Use screen reads only; never read or edit calendar data."
        ),
        AppToolPack(
            appName: "Mail",
            aliases: ["mail"],
            toolNames: ["screen.ocr", "screen.ui_elements", "screen.snapshot"],
            guidance: "Use screen reads only; never query Mail through Automation."
        ),
        AppToolPack(
            appName: "Music",
            aliases: ["music"],
            toolNames: ["screen.ocr", "screen.ui_elements", "screen.snapshot"],
            guidance: "Use screen reads only; never control playback."
        ),
        AppToolPack(
            appName: "Finder",
            aliases: ["finder"],
            toolNames: ["screen.ocr", "screen.ui_elements", "screen.snapshot"],
            guidance: "Use screen reads only; never reveal or open files."
        )
    ]

    public static func matching(applicationName: String?) -> AppToolPack? {
        guard let app = applicationName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !app.isEmpty else {
            return nil
        }
        return all.first { pack in
            pack.aliases.contains { app.contains($0) }
        }
    }
}
