import Foundation

enum ScreenTextRedactor {
    static func redact(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return text
        }
        if isNotificationBanner(trimmed) {
            return "[redacted notification]"
        }
        if isSensitiveField(trimmed) {
            return "[redacted sensitive field]"
        }

        var redacted = trimmed
        redacted = replace(pattern: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, in: redacted, with: "[redacted email]")
        redacted = replace(pattern: #"\b(?:\+?\d[\d -]{7,}\d)\b"#, in: redacted, with: "[redacted phone]")
        redacted = replace(pattern: #"\b\d{6}\b"#, in: redacted, with: "[redacted code]")
        return redacted
    }

    private static func isNotificationBanner(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("notification")
            || lowercased.contains("message from")
            || lowercased.contains("reminder")
            || lowercased.contains("calendar alert")
    }

    private static func isSensitiveField(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("password")
            || lowercased.contains("passcode")
            || lowercased.contains("verification code")
            || lowercased.contains("one-time code")
            || lowercased.contains("security code")
            || lowercased.contains("api key")
            || lowercased.contains("secret")
            || lowercased.contains("token")
    }

    private static func replace(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
