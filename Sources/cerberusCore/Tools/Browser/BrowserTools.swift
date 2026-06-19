import AppKit
import Foundation
import FoundationModels

@Generable
public enum BrowserApp: String, Codable, Sendable {
    case safari
    case chrome

    var displayName: String {
        switch self {
        case .safari:
            "Safari"
        case .chrome:
            "Chrome"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .safari:
            "com.apple.Safari"
        case .chrome:
            "com.google.Chrome"
        }
    }
}

public struct BrowserTabSnapshot: Equatable, Sendable {
    public let browser: BrowserApp
    public let windowIndex: Int
    public let tabIndex: Int
    public let isActive: Bool
    public let title: String
    public let url: String

    public init(browser: BrowserApp, windowIndex: Int, tabIndex: Int, isActive: Bool, title: String, url: String) {
        self.browser = browser
        self.windowIndex = windowIndex
        self.tabIndex = tabIndex
        self.isActive = isActive
        self.title = title
        self.url = url
    }
}

public protocol BrowserTabsRunning: Sendable {
    func tabs(for browser: BrowserApp?) async throws -> [BrowserTabSnapshot]
}

public protocol BrowserOpenURLRunning: Sendable {
    func open(url: URL, in browser: BrowserApp) async throws -> String
}

public struct BrowserAppleScriptTabsRunner: BrowserTabsRunning {
    public init() {}

    public func tabs(for browser: BrowserApp?) async throws -> [BrowserTabSnapshot] {
        let browsers = browser.map { [$0] } ?? [.safari, .chrome]
        var snapshots: [BrowserTabSnapshot] = []
        for browser in browsers {
            snapshots += try await tabs(for: browser)
        }
        return snapshots
    }

    private func tabs(for browser: BrowserApp) async throws -> [BrowserTabSnapshot] {
        try await MainActor.run {
            guard Self.isRunning(browser) else {
                return []
            }

            guard let script = NSAppleScript(source: Self.script(for: browser)) else {
                throw ToolExecutionError.denied("Could not prepare \(browser.displayName) automation script.")
            }

            var errorInfo: NSDictionary?
            let output = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "\(browser.displayName) AppleScript failed."
                throw ToolExecutionError.denied(message)
            }
            return Self.parseRows(output.stringValue ?? "", browser: browser)
        }
    }

    @MainActor
    private static func isRunning(_ browser: BrowserApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == browser.bundleIdentifier
        }
    }

    static func parseRows(_ text: String, browser: BrowserApp) -> [BrowserTabSnapshot] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> BrowserTabSnapshot? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 5,
                      let windowIndex = Int(fields[0]),
                      let tabIndex = Int(fields[1]) else {
                    return nil
                }
                return BrowserTabSnapshot(
                    browser: browser,
                    windowIndex: windowIndex,
                    tabIndex: tabIndex,
                    isActive: fields[2] == "true",
                    title: fields[3],
                    url: sanitizedURL(fields[4])
                )
            }
    }

    private static func script(for browser: BrowserApp) -> String {
        switch browser {
        case .safari:
            """
            set rows to {}
            tell application "Safari"
                repeat with windowItem in windows
                    set windowIndex to index of windowItem
                    set activeTab to current tab of windowItem
                    repeat with tabItem in tabs of windowItem
                        set activeText to "false"
                        if tabItem is activeTab then set activeText to "true"
                        set end of rows to ((windowIndex as text) & tab & ((index of tabItem) as text) & tab & activeText & tab & (name of tabItem as text) & tab & (URL of tabItem as text))
                    end repeat
                end repeat
            end tell
            set previousDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to linefeed
            set outputText to rows as text
            set AppleScript's text item delimiters to previousDelimiters
            return outputText
            """
        case .chrome:
            """
            set rows to {}
            tell application "Google Chrome"
                repeat with windowItem in windows
                    set windowIndex to index of windowItem
                    set activeIndex to active tab index of windowItem
                    set tabIndex to 1
                    repeat with tabItem in tabs of windowItem
                        set activeText to "false"
                        if tabIndex is activeIndex then set activeText to "true"
                        set end of rows to ((windowIndex as text) & tab & (tabIndex as text) & tab & activeText & tab & (title of tabItem as text) & tab & (URL of tabItem as text))
                        set tabIndex to tabIndex + 1
                    end repeat
                end repeat
            end tell
            set previousDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to linefeed
            set outputText to rows as text
            set AppleScript's text item delimiters to previousDelimiters
            return outputText
            """
        }
    }
}

public struct BrowserWorkspaceOpenURLRunner: BrowserOpenURLRunning {
    public init() {}

    public func open(url: URL, in browser: BrowserApp) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) else {
                continuation.resume(throwing: ToolExecutionError.denied("\(browser.displayName) is not installed."))
                return
            }

            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: ToolExecutionError.denied(error.localizedDescription))
                } else {
                    continuation.resume(returning: "Opened \(Self.displayURL(url.absoluteString)) in \(browser.displayName).")
                }
            }
            }
        }
    }

    private static func displayURL(_ value: String) -> String {
        BrowserAppleScriptTabsRunner.sanitizedURL(value)
    }
}

public struct BrowserTabsTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let browser: BrowserApp?
        public let limit: Int

        public init(browser: BrowserApp? = nil, limit: Int = 20) {
            self.browser = browser
            self.limit = limit
        }
    }

    public let name = "browser.tabs"
    public let capability = "Read open Safari or Chrome tab titles and sanitized URLs."
    public let mutatesState = false
    public let argumentSchema = #"{"browser":"optional safari|chrome","limit":20}"#

    private let runner: any BrowserTabsRunning

    public init(runner: any BrowserTabsRunning = BrowserAppleScriptTabsRunner()) {
        self.runner = runner
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let limit = ToolArgumentSupport.clampLimit(arguments.limit)
        let tabs = Array(try await runner.tabs(for: arguments.browser).prefix(limit))
        let payload = tabs.map(Self.format).joined(separator: "\n")
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: tabs.count == 1 ? "Found 1 browser tab." : "Found \(tabs.count) browser tabs.",
            untrustedPayload: payload.isEmpty ? "No browser tabs found." : payload,
            metadata: ["count": "\(tabs.count)"]
        )
    }

    static func format(_ tab: BrowserTabSnapshot) -> String {
        let active = tab.isActive ? " active" : ""
        return "- \(tab.browser.displayName) window \(tab.windowIndex) tab \(tab.tabIndex)\(active): \(tab.title) \(tab.url)"
    }
}

public struct BrowserOpenURLTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let url: String
        public let browser: BrowserApp

        public init(url: String, browser: BrowserApp) {
            self.url = url
            self.browser = browser
        }
    }

    public let name = "browser.open_url"
    public let capability = "Open an HTTP or HTTPS URL in Safari or Chrome. Requires explicit confirmation."
    public let mutatesState = true
    public let argumentSchema = #"{"url":"https://example.com","browser":"safari|chrome"}"#

    private let runner: any BrowserOpenURLRunning

    public init(runner: any BrowserOpenURLRunning = BrowserWorkspaceOpenURLRunner()) {
        self.runner = runner
    }

    public func validate(_ arguments: Arguments) throws {
        _ = try Self.validatedURL(arguments.url)
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let url = try Self.validatedURL(arguments.url)
        let summary = try await runner.open(url: url, in: arguments.browser)
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: summary,
            untrustedPayload: summary
        )
    }

    static func validatedURL(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            throw ToolExecutionError.invalidArguments("url must be http or https")
        }
        return url
    }
}

extension BrowserAppleScriptTabsRunner {
    static func sanitizedURL(_ value: String) -> String {
        guard var components = URLComponents(string: value) else {
            return value
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? value
    }
}
