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
            toolNames: ["files.search", "finder.selection", "shell.run"],
            guidance: "Use project and Finder context first; use shell.run only for explicit command requests."
        ),
        AppToolPack(
            appName: "Terminal",
            aliases: ["terminal", "iterm"],
            toolNames: ["files.search", "finder.selection", "shell.run"],
            guidance: "Use project and Finder context first; preserve shell confirmation semantics."
        ),
        AppToolPack(
            appName: "Safari",
            aliases: ["safari"],
            toolNames: ["browser.tabs", "browser.open_url", "screen.ocr", "screen.ui_elements", "web.search"],
            guidance: "Use browser.tabs for tab context; browser.open_url changes browser state and requires confirmation."
        ),
        AppToolPack(
            appName: "Chrome",
            aliases: ["chrome", "google chrome"],
            toolNames: ["browser.tabs", "browser.open_url", "screen.ocr", "screen.ui_elements", "web.search"],
            guidance: "Use browser.tabs for tab context; browser.open_url changes browser state and requires confirmation."
        ),
        AppToolPack(
            appName: "Calendar",
            aliases: ["calendar"],
            toolNames: ["calendar.read", "calendar.create", "calendar.edit", "calendar.delete"],
            guidance: "Use calendar.read for schedule questions; write tools require confirmation."
        ),
        AppToolPack(
            appName: "Mail",
            aliases: ["mail"],
            toolNames: ["mail.search"],
            guidance: "Use mail.search for read-only lookup; body search remains opt-in."
        ),
        AppToolPack(
            appName: "Music",
            aliases: ["music"],
            toolNames: ["music.now_playing", "music.control"],
            guidance: "Use music.now_playing for status; music.control requires confirmation."
        ),
        AppToolPack(
            appName: "Finder",
            aliases: ["finder"],
            toolNames: ["finder.selection", "finder.reveal", "files.search"],
            guidance: "Use finder.selection for current context; finder.reveal changes Finder UI state and requires confirmation."
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
