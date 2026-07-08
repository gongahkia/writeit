import Foundation

public enum AssistantPlanPolicy {
    private static let refusalResponse = "I can observe the screen, but I cannot operate apps, hide activity, or help with unauthorized surveillance or cheating."

    public static func preflightPlan(
        for request: String
    ) -> AssistantPlan? {
        let text = RequestText(request)
        return isUnsafe(text) ? refusal() : nil
    }

    public static func replacementPlan(
        for request: String,
        context: AssistantContext = AssistantContext()
    ) -> AssistantPlan? {
        let text = RequestText(request)
        if isUnsafe(text) {
            return refusal()
        }

        let allowedTools = Set(context.allowedToolNames)
        if allowedTools.contains("screen.barcodes"), text.hasAnyWord(["barcode", "barcodes", "qr"]) {
            return toolPlan(
                name: "screen.barcodes",
                argumentsJSON: #"{"limit":10,"scope":"main_display"}"#,
                summary: "main display barcodes"
            )
        }
        if allowedTools.contains("screen.ui_elements"), shouldReadUIElements(text) {
            return toolPlan(
                name: "screen.ui_elements",
                argumentsJSON: #"{"limit":30}"#,
                summary: "active app UI elements"
            )
        }
        if allowedTools.contains("screen.ocr"), shouldReadText(text) {
            let scope = text.containsPhrase("active window") ? "active_window" : "main_display"
            return toolPlan(
                name: "screen.ocr",
                argumentsJSON: #"{"limit":20,"scope":"\#(scope)"}"#,
                summary: scope == "active_window" ? "active window text" : "main display text"
            )
        }
        if allowedTools.contains("screen.snapshot"), shouldCaptureScreen(text) {
            return toolPlan(
                name: "screen.snapshot",
                argumentsJSON: #"{"scope":"main_display"}"#,
                summary: "main display snapshot"
            )
        }
        return nil
    }

    public static func normalized(
        _ plan: AssistantPlan,
        request: String,
        context: AssistantContext = AssistantContext()
    ) -> AssistantPlan {
        if let replacement = replacementPlan(for: request, context: context) {
            return replacement
        }
        if plan.intent == .refuseUnsafeRequest {
            return refusal(spokenResponse: plan.spokenResponse)
        }
        if !plan.toolName.isEmpty, context.allowedToolNames.contains(plan.toolName), isScreenTool(plan.toolName) {
            return AssistantPlan(
                intent: .callTool,
                spokenResponse: plan.spokenResponse,
                requiresConfirmation: false,
                toolName: plan.toolName,
                toolArgumentsJSON: plan.toolArgumentsJSON.isEmpty ? "{}" : plan.toolArgumentsJSON,
                toolArgumentsSummary: plan.toolArgumentsSummary
            )
        }
        return plan
    }

    private static func refusal(spokenResponse: String = Self.refusalResponse) -> AssistantPlan {
        AssistantPlan(
            intent: .refuseUnsafeRequest,
            spokenResponse: spokenResponse,
            requiresConfirmation: false
        )
    }

    private static func toolPlan(name: String, argumentsJSON: String, summary: String) -> AssistantPlan {
        AssistantPlan(
            intent: .callTool,
            spokenResponse: "I will check the screen.",
            requiresConfirmation: false,
            toolName: name,
            toolArgumentsJSON: argumentsJSON,
            toolArgumentsSummary: summary
        )
    }

    private static func shouldReadText(_ text: RequestText) -> Bool {
        text.containsAnyPhrase([
            "what text",
            "read the active window",
            "read my screen",
            "read the screen",
            "visible text"
        ])
    }

    private static func shouldReadUIElements(_ text: RequestText) -> Bool {
        text.hasAnyWord(["control", "controls", "button", "buttons"])
            || text.containsAnyPhrase([
                "ui elements",
                "visible in this app",
                "what is visible in this app"
            ])
    }

    private static func shouldCaptureScreen(_ text: RequestText) -> Bool {
        text.hasAnyWord(["capture", "screenshot", "snapshot"])
            && (text.hasAnyWord(["screen"]) || text.containsPhrase("looking at"))
    }

    private static func isUnsafe(_ text: RequestText) -> Bool {
        if text.hasAnyWord(["click", "type", "press", "tap", "drag", "scroll", "operate", "run"]) {
            return true
        }
        if text.hasWord("calendar") && text.hasAnyWord(["create", "event", "open"]) {
            return true
        }
        if text.hasWord("reminder") && text.hasAnyWord(["add", "create"]) {
            return true
        }
        if text.hasWord("shortcut") && text.hasAnyWord(["run", "use"]) {
            return true
        }
        if text.hasWord("mail") && text.hasAnyWord(["find", "search"]) {
            return true
        }
        if text.hasWord("contacts") && text.hasAnyWord(["find", "search"]) {
            return true
        }
        if text.hasWord("notes") && text.hasAnyWord(["find", "search"]) {
            return true
        }
        if text.hasWord("music") && text.hasAnyWord(["pause", "play", "skip"]) {
            return true
        }
        if text.hasWord("files") && text.hasAnyWord(["find", "search"]) {
            return true
        }
        if text.hasWord("web") && text.hasWord("search") {
            return true
        }
        if text.hasWord("remember") {
            return true
        }
        if text.containsAnyPhrase([
            "open calendar",
            "create a calendar",
            "calendar event",
            "create a reminder",
            "shortcut",
            "search mail",
            "my contacts",
            "search notes",
            "pause music",
            "search files",
            "search the web",
            "remember that",
            "ask you to remember",
            "call this mcp",
            "list mcp",
            "mcp prompt",
            "use the screen image to click",
            "operate this ui",
            "record and summarize this meeting without",
            "listen to my coworkers conversation",
            "window invisible",
            "share my screen"
        ]) {
            return true
        }
        if text.hasWord("mcp") {
            return true
        }
        if text.hasAnyWord(["exam", "proctor", "proctoring", "interview", "interviewer"])
            && text.hasAnyWord(["answer", "answers", "hide", "without", "silently", "pass"]) {
            return true
        }
        if text.hasAnyWord(["coworkers", "coworker"]) && text.hasAnyWord(["listen", "conversation"]) {
            return true
        }
        return false
    }

    private static func isScreenTool(_ toolName: String) -> Bool {
        [
            "screen.barcodes",
            "screen.describe",
            "screen.ocr",
            "screen.snapshot",
            "screen.ui_elements"
        ].contains(toolName)
    }
}

private struct RequestText {
    private let words: Set<String>
    private let paddedText: String

    init(_ rawValue: String) {
        let folded = rawValue.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let parts = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        words = Set(parts)
        paddedText = " \(parts.joined(separator: " ")) "
    }

    func hasWord(_ word: String) -> Bool {
        words.contains(word)
    }

    func hasAnyWord(_ candidates: [String]) -> Bool {
        candidates.contains { words.contains($0) }
    }

    func containsPhrase(_ phrase: String) -> Bool {
        paddedText.contains(" \(phrase) ")
    }

    func containsAnyPhrase(_ phrases: [String]) -> Bool {
        phrases.contains { containsPhrase($0) }
    }
}
