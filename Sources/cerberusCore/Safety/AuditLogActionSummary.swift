import Foundation

public enum AuditLogActionSummary {
    public static func lastToolActionSummary(from entries: [AuditLogEntry]) -> String {
        guard let latest = entries.first else {
            return "No tool calls recorded yet."
        }

        return "Last tool call: \(latest.toolName). Result: \(latest.resultSummary)"
    }
}
