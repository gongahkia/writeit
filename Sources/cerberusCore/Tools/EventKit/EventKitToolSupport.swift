@preconcurrency import EventKit
import Foundation

enum EventKitToolSupport {
    static func requireAccess(to entityType: EKEntityType) throws {
        let status = EKEventStore.authorizationStatus(for: entityType)
        guard status == .fullAccess else {
            throw ToolExecutionError.denied("EventKit access is not granted for \(entityType).")
        }
    }

    static func parseDate(_ value: String?, default defaultDate: @autoclosure () -> Date) throws -> Date {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultDate()
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        throw ToolExecutionError.invalidArguments("Invalid ISO8601 date: \(value)")
    }

}
