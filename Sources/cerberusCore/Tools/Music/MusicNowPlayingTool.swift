import AppKit
import Foundation

public struct MusicNowPlayingTool: AssistantTool {
    public struct Arguments: Codable, Sendable {
        public init() {}
    }

    public let name = "music.now_playing"
    public let capability = "Read the current track from the macOS Music app."
    public let mutatesState = false

    public init() {}

    public func run(arguments: Arguments) async throws -> ToolResult {
        try await MainActor.run {
            guard musicIsRunning else {
                return ToolResult(
                    toolName: name,
                    succeeded: true,
                    spokenSummary: "Music is not running.",
                    untrustedPayload: "Music is not running."
                )
            }

            var errorInfo: NSDictionary?
            guard let script = NSAppleScript(source: appleScript) else {
                throw ToolExecutionError.denied("Could not prepare Music automation script.")
            }

            let output = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                throw ToolExecutionError.denied(errorInfo.description)
            }

            let text = output.stringValue ?? "No track information is available."
            return ToolResult(
                toolName: name,
                succeeded: true,
                spokenSummary: text,
                untrustedPayload: text
            )
        }
    }

    @MainActor
    private var musicIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music"
        }
    }

    private var appleScript: String {
        """
        tell application "Music"
            if player state is stopped then
                return "Music is stopped."
            end if

            set trackName to "Unknown track"
            set artistName to "Unknown artist"
            set albumName to "Unknown album"

            try
                set trackName to name of current track
            end try
            try
                set artistName to artist of current track
            end try
            try
                set albumName to album of current track
            end try

            return trackName & " by " & artistName & " from " & albumName
        end tell
        """
    }
}
