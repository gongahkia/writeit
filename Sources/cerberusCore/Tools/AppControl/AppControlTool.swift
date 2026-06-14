import AppKit
import Foundation

public enum AppControlAction: String, Codable, Sendable {
    case open
    case focus
    case quit
}

public struct AppControlTool: AssistantTool {
    public struct Arguments: Codable, Sendable {
        public let action: AppControlAction
        public let applicationName: String
        public let bundleIdentifier: String?

        public init(action: AppControlAction, applicationName: String, bundleIdentifier: String? = nil) {
            self.action = action
            self.applicationName = applicationName
            self.bundleIdentifier = bundleIdentifier
        }
    }

    public let name = "app.control"
    public let capability = "Open, focus, or quit a macOS application by visible name or bundle identifier."
    public let mutatesState = true
    public let argumentSchema = #"{"action":"open|focus|quit","applicationName":"Calendar","bundleIdentifier":"optional.bundle.id"}"#

    public init() {}

    public func validate(_ arguments: Arguments) throws {
        let hasName = !arguments.applicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasBundleID = !(arguments.bundleIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard hasName || hasBundleID else {
            throw ToolExecutionError.invalidArguments("applicationName or bundleIdentifier is required")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        try await MainActor.run {
            switch arguments.action {
            case .open:
                return try open(arguments)
            case .focus:
                return try focus(arguments)
            case .quit:
                return try quit(arguments)
            }
        }
    }

    @MainActor
    private func open(_ arguments: Arguments) throws -> ToolResult {
        if let runningApp = findRunningApplication(arguments) {
            runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return result("Focused \(displayName(arguments)).")
        }

        guard let appURL = applicationURL(arguments) else {
            throw ToolExecutionError.denied("Could not find \(displayName(arguments)) in installed applications.")
        }

        let opened = NSWorkspace.shared.open(appURL)
        return result(opened ? "Opened \(displayName(arguments))." : "Could not open \(displayName(arguments)).")
    }

    @MainActor
    private func focus(_ arguments: Arguments) throws -> ToolResult {
        guard let runningApp = findRunningApplication(arguments) else {
            throw ToolExecutionError.denied("\(displayName(arguments)) is not running.")
        }

        runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        return result("Focused \(displayName(arguments)).")
    }

    @MainActor
    private func quit(_ arguments: Arguments) throws -> ToolResult {
        guard let runningApp = findRunningApplication(arguments) else {
            return result("\(displayName(arguments)) is not running.")
        }

        let terminated = runningApp.terminate()
        return result(terminated ? "Asked \(displayName(arguments)) to quit." : "Could not quit \(displayName(arguments)).")
    }

    @MainActor
    private func findRunningApplication(_ arguments: Arguments) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            if let bundleIdentifier = arguments.bundleIdentifier, app.bundleIdentifier == bundleIdentifier {
                return true
            }

            return app.localizedName?.localizedCaseInsensitiveCompare(arguments.applicationName) == .orderedSame
        }
    }

    @MainActor
    private func applicationURL(_ arguments: Arguments) -> URL? {
        if let bundleIdentifier = arguments.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return url
        }

        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: arguments.applicationName)
            ?? applicationURLByName(arguments.applicationName)
    }

    private func applicationURLByName(_ applicationName: String) -> URL? {
        let trimmedName = applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            "/Applications/\(trimmedName).app",
            "\(NSHomeDirectory())/Applications/\(trimmedName).app",
            "/System/Applications/\(trimmedName).app"
        ]

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func displayName(_ arguments: Arguments) -> String {
        if !arguments.applicationName.isEmpty {
            return arguments.applicationName
        }
        return arguments.bundleIdentifier ?? "application"
    }

    private func result(_ summary: String) -> ToolResult {
        ToolResult(toolName: name, succeeded: true, spokenSummary: summary)
    }
}
