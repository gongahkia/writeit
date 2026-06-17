import AppKit
import Foundation
import FoundationModels

@Generable
public enum MusicControlAction: Codable, Sendable {
    case play
    case pause
    case playPause
    case stop
    case nextTrack
    case previousTrack
}

public protocol MusicControlRunning: Sendable {
    func perform(_ action: MusicControlAction) async throws -> String
}

public struct MusicAppleScriptControlRunner: MusicControlRunning {
    public init() {}

    public func perform(_ action: MusicControlAction) async throws -> String {
        try await MainActor.run {
            guard Self.musicIsRunning else {
                return "Music is not running."
            }

            var errorInfo: NSDictionary?
            guard let script = NSAppleScript(source: Self.appleScript(for: action)) else {
                throw ToolExecutionError.denied("Could not prepare Music automation script.")
            }

            let output = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                throw ToolExecutionError.denied(errorInfo.description)
            }

            return output.stringValue ?? "Music command completed."
        }
    }

    @MainActor
    private static var musicIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music"
        }
    }

    private static func appleScript(for action: MusicControlAction) -> String {
        let command = switch action {
        case .play:
            "play"
        case .pause:
            "pause"
        case .playPause:
            "playpause"
        case .stop:
            "stop"
        case .nextTrack:
            "next track"
        case .previousTrack:
            "previous track"
        }

        return """
        tell application "Music"
            \(command)
            set stateText to player state as text
            set detailText to "Music " & stateText & "."

            try
                if player state is not stopped then
                    set trackName to name of current track
                    set artistName to artist of current track
                    set detailText to detailText & " " & trackName & " by " & artistName & "."
                end if
            end try

            return detailText
        end tell
        """
    }
}

public struct MusicControlTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let action: MusicControlAction

        public init(action: MusicControlAction) {
            self.action = action
        }
    }

    public let name = "music.control"
    public let capability = "Control playback in the macOS Music app with play, pause, play/pause, stop, next, or previous."
    public let mutatesState = true
    public let argumentSchema = #"{"action":"play|pause|playPause|stop|nextTrack|previousTrack"}"#

    private let runner: any MusicControlRunning

    public init(runner: any MusicControlRunning = MusicAppleScriptControlRunner()) {
        self.runner = runner
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        let summary = try await runner.perform(arguments.action)
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: summary,
            untrustedPayload: summary
        )
    }
}
