@preconcurrency import EventKit
import Foundation

public struct CalendarTool: AssistantTool {
    public struct Arguments: Codable, Sendable {
        public let startDateISO8601: String?
        public let endDateISO8601: String?
        public let calendarNames: [String]
        public let limit: Int

        public init(
            startDateISO8601: String? = nil,
            endDateISO8601: String? = nil,
            calendarNames: [String] = [],
            limit: Int = 10
        ) {
            self.startDateISO8601 = startDateISO8601
            self.endDateISO8601 = endDateISO8601
            self.calendarNames = calendarNames
            self.limit = limit
        }
    }

    public let name = "calendar.read"
    public let capability = "Read upcoming calendar events in a bounded date range."
    public let mutatesState = false

    public init() {}

    public func run(arguments: Arguments) async throws -> ToolResult {
        try EventKitToolSupport.requireAccess(to: .event)

        let now = Date()
        let startDate = try EventKitToolSupport.parseDate(arguments.startDateISO8601, default: now)
        let endDate = try EventKitToolSupport.parseDate(
            arguments.endDateISO8601,
            default: Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        )
        let limit = ToolArgumentSupport.clampLimit(arguments.limit)
        let eventStore = EKEventStore()
        let calendars = selectedCalendars(arguments.calendarNames, eventStore: eventStore)
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendars
        )

        let events = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)

        let payload = events
            .map(formatEvent)
            .joined(separator: "\n")

        let count = events.count
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: count == 1 ? "Found 1 calendar event." : "Found \(count) calendar events.",
            untrustedPayload: payload,
            metadata: [
                "count": "\(count)",
                "start": ISO8601DateFormatter().string(from: startDate),
                "end": ISO8601DateFormatter().string(from: endDate)
            ]
        )
    }

    private func selectedCalendars(_ names: [String], eventStore: EKEventStore) -> [EKCalendar]? {
        guard !names.isEmpty else {
            return nil
        }

        let normalizedNames = Set(names.map { $0.lowercased() })
        return eventStore.calendars(for: .event).filter { calendar in
            normalizedNames.contains(calendar.title.lowercased())
        }
    }

    private func formatEvent(_ event: EKEvent) -> String {
        let formatter = ISO8601DateFormatter()
        let start = formatter.string(from: event.startDate)
        let end = formatter.string(from: event.endDate)
        let calendarName = event.calendar?.title ?? "Unknown calendar"
        return "- \(start) to \(end) [\(calendarName)] \(event.title ?? "Untitled event")"
    }
}
