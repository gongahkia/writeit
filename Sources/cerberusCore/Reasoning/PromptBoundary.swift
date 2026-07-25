import Foundation

public enum PromptBoundary {
    public static func untrustedBlock(tag: String = "tool-output", content: String) -> String {
        let safeTag = sanitizedTag(tag)
        return """
        <\(safeTag)>
        \(escapeClosingTags(in: content, tag: safeTag))
        </\(safeTag)>
        """
    }

    public static func escapeClosingTags(in content: String, tag: String) -> String {
        let safeTag = sanitizedTag(tag)
        let pattern = #"(?i)</\s*\#(NSRegularExpression.escapedPattern(for: safeTag))\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return content
        }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.stringByReplacingMatches(
            in: content,
            options: [],
            range: range,
            withTemplate: "[escaped closing \(safeTag) tag]"
        )
    }

    private static func sanitizedTag(_ tag: String) -> String {
        let scalars = tag.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar.value == 45 ? Character(scalar) : "-"
        }
        let sanitized = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
        return sanitized.isEmpty ? "untrusted-data" : sanitized
    }
}
