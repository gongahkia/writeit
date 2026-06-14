import Foundation

public struct WebSearchTool: AssistantTool {
    public struct Arguments: Codable, Sendable {
        public let query: String
        public let site: String?
        public let limit: Int

        public init(query: String, site: String? = nil, limit: Int = 5) {
            self.query = query
            self.site = site
            self.limit = limit
        }
    }

    public let name = "web.search"
    public let capability = "Search the web through an allowlisted HTTPS endpoint."
    public let mutatesState = false
    public let argumentSchema = #"{"query":"search terms","site":"optional allowlisted domain","limit":5}"#

    private let allowedDomains: Set<String>

    public init(allowedDomains: Set<String> = ["duckduckgo.com", "wikipedia.org", "developer.apple.com"]) {
        self.allowedDomains = allowedDomains
    }

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("query is required")
        }

        if let site = arguments.site, !site.isEmpty, !allowedDomains.contains(site) {
            throw ToolExecutionError.denied("Domain is not allowlisted: \(site)")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let limit = ToolArgumentSupport.clampLimit(arguments.limit, default: 5, maximum: 10)
        let url = try searchURL(query: scopedQuery(arguments))
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ToolExecutionError.denied("Search request failed.")
        }

        let html = String(decoding: data, as: UTF8.self)
        let text = HTMLTextExtractor.plainText(from: html, maxCharacters: 4_000)

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Search completed.",
            untrustedPayload: text,
            metadata: [
                "endpoint": url.host ?? "unknown",
                "limit": "\(limit)"
            ]
        )
    }

    private func scopedQuery(_ arguments: Arguments) -> String {
        guard let site = arguments.site, !site.isEmpty else {
            return arguments.query
        }

        return "site:\(site) \(arguments.query)"
    }

    private func searchURL(query: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "duckduckgo.com"
        components.path = "/html/"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "kl", value: "us-en"),
            URLQueryItem(name: "kp", value: "-2")
        ]

        guard let url = components.url, url.scheme == "https", url.host == "duckduckgo.com" else {
            throw ToolExecutionError.invalidArguments("Could not construct a safe search URL.")
        }

        return url
    }
}

private enum HTMLTextExtractor {
    static func plainText(from html: String, maxCharacters: Int) -> String {
        var text = html
        text = replace(pattern: "<script[\\s\\S]*?</script>", in: text, with: " ")
        text = replace(pattern: "<style[\\s\\S]*?</style>", in: text, with: " ")
        text = replace(pattern: "<[^>]+>", in: text, with: " ")
        text = decodeEntities(text)
        text = replace(pattern: "\\s+", in: text, with: " ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.count > maxCharacters {
            return String(text.prefix(maxCharacters))
        }
        return text
    }

    private static func replace(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
