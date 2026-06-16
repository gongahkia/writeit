@preconcurrency import EventKit
import Foundation
import FoundationModels

public struct CalendarTool: AssistantTool {
    @Generable
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
    public let argumentSchema = #"{"startDateISO8601":"optional ISO8601","endDateISO8601":"optional ISO8601","calendarNames":[],"limit":10}"#

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

public struct CalendarCreateTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let title: String
        public let startDateISO8601: String
        public let endDateISO8601: String?
        public let durationMinutes: Int?
        public let calendarName: String?
        public let location: String?
        public let notes: String?
        public let isAllDay: Bool

        public init(
            title: String,
            startDateISO8601: String,
            endDateISO8601: String? = nil,
            durationMinutes: Int? = nil,
            calendarName: String? = nil,
            location: String? = nil,
            notes: String? = nil,
            isAllDay: Bool = false
        ) {
            self.title = title
            self.startDateISO8601 = startDateISO8601
            self.endDateISO8601 = endDateISO8601
            self.durationMinutes = durationMinutes
            self.calendarName = calendarName
            self.location = location
            self.notes = notes
            self.isAllDay = isAllDay
        }
    }

    public let name = "calendar.create"
    public let capability = "Create a calendar event in the default or named calendar. Requires explicit confirmation."
    public let mutatesState = true
    public let argumentSchema = #"{"title":"Dentist","startDateISO8601":"2026-06-16T09:00:00Z","endDateISO8601":"optional ISO8601","durationMinutes":"optional positive integer","calendarName":"optional calendar name","location":"optional","notes":"optional","isAllDay":false}"#

    public init() {}

    public func validate(_ arguments: Arguments) throws {
        _ = try normalizedTitle(arguments.title)
        let startDate = try EventKitToolSupport.parseDate(arguments.startDateISO8601, default: Date())
        let endDate = try resolvedEndDate(arguments: arguments, startDate: startDate)
        guard endDate > startDate else {
            throw ToolExecutionError.invalidArguments("Calendar event end must be after start.")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        try validate(arguments)
        try EventKitToolSupport.requireAccess(to: .event)

        let eventStore = EKEventStore()
        let startDate = try EventKitToolSupport.parseDate(arguments.startDateISO8601, default: Date())
        let endDate = try resolvedEndDate(arguments: arguments, startDate: startDate)
        let event = EKEvent(eventStore: eventStore)
        event.title = try normalizedTitle(arguments.title)
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = arguments.isAllDay
        event.calendar = try selectedCalendar(arguments.calendarName, eventStore: eventStore)
        event.location = arguments.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        event.notes = arguments.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        try eventStore.save(event, span: .thisEvent, commit: true)
        let calendarName = event.calendar?.title ?? "default calendar"
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Calendar event created.",
            untrustedPayload: Self.payload(
                title: event.title,
                calendarName: calendarName,
                startDate: startDate,
                endDate: endDate
            ),
            metadata: [
                "title": event.title,
                "calendar": calendarName,
                "start": ISO8601DateFormatter().string(from: startDate),
                "end": ISO8601DateFormatter().string(from: endDate)
            ]
        )
    }

    static func payload(title: String, calendarName: String, startDate: Date, endDate: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return "Created calendar event: [\(calendarName)] \(title) from \(formatter.string(from: startDate)) to \(formatter.string(from: endDate))"
    }

    private func normalizedTitle(_ title: String) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ToolExecutionError.invalidArguments("Calendar event title is required.")
        }
        return normalized
    }

    private func resolvedEndDate(arguments: Arguments, startDate: Date) throws -> Date {
        if let endDateISO8601 = arguments.endDateISO8601?.trimmingCharacters(in: .whitespacesAndNewlines), !endDateISO8601.isEmpty {
            return try EventKitToolSupport.parseDate(endDateISO8601, default: startDate)
        }
        let durationMinutes = arguments.durationMinutes ?? 30
        guard durationMinutes > 0, durationMinutes <= 24 * 60 else {
            throw ToolExecutionError.invalidArguments("Calendar event durationMinutes must be in 1...1440.")
        }
        return Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startDate) ?? startDate
    }

    private func selectedCalendar(_ calendarName: String?, eventStore: EKEventStore) throws -> EKCalendar {
        if let calendarName = calendarName?.trimmingCharacters(in: .whitespacesAndNewlines), !calendarName.isEmpty {
            if let calendar = eventStore.calendars(for: .event).first(where: {
                $0.title.localizedCaseInsensitiveCompare(calendarName) == .orderedSame
            }) {
                return calendar
            }
            throw ToolExecutionError.invalidArguments("Calendar not found: \(calendarName)")
        }

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw ToolExecutionError.denied("No default calendar is available.")
        }
        return calendar
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
