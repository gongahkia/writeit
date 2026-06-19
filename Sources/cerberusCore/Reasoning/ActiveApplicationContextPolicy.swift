import Foundation

public enum ActiveApplicationContextPolicy {
    public static func hints(for applicationName: String?, allowedToolNames: [String]) -> [String] {
        guard let applicationName = applicationName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !applicationName.isEmpty else {
            return []
        }

        let app = applicationName.lowercased()
        let allowed = Set(allowedToolNames)
        var hints: [String] = []

        if app.contains("xcode") || app.contains("terminal") || app.contains("iterm") || app.contains("visual studio code") {
            append("Prefer project workspace hints and files.search for coding context.", ifAllowed: "files.search", in: allowed, to: &hints)
            append("Use shell.run only for explicit command requests and keep confirmation semantics.", ifAllowed: "shell.run", in: allowed, to: &hints)
        }
        if app.contains("finder") {
            append("Prefer files.search for filename lookup inside approved folders.", ifAllowed: "files.search", in: allowed, to: &hints)
        }
        if app.contains("safari") || app.contains("chrome") {
            append("Prefer screen.ocr for visible page text and web.search for current public facts.", ifAnyAllowed: ["screen.ocr", "web.search"], in: allowed, to: &hints)
        }
        if app.contains("calendar") {
            append("Prefer calendar.read for schedule questions and calendar.create only for explicit event creation.", ifAnyAllowed: ["calendar.read", "calendar.create"], in: allowed, to: &hints)
        }
        if app.contains("mail") {
            append("Prefer mail.search for read-only mail lookup; body search remains opt-in.", ifAllowed: "mail.search", in: allowed, to: &hints)
        }
        if app.contains("music") {
            append("Prefer music.nowPlaying for read-only status and music.control only for explicit playback changes.", ifAnyAllowed: ["music.nowPlaying", "music.control"], in: allowed, to: &hints)
        }

        return hints
    }

    private static func append(_ hint: String, ifAllowed toolName: String, in allowed: Set<String>, to hints: inout [String]) {
        guard allowed.contains(toolName) else {
            return
        }
        hints.append(hint)
    }

    private static func append(_ hint: String, ifAnyAllowed toolNames: [String], in allowed: Set<String>, to hints: inout [String]) {
        guard toolNames.contains(where: allowed.contains) else {
            return
        }
        hints.append(hint)
    }
}
