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

public struct CalendarEditTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let title: String
        public let calendarName: String?
        public let startDateISO8601: String?
        public let endDateISO8601: String?
        public let newTitle: String?
        public let newCalendarName: String?
        public let newStartDateISO8601: String?
        public let newEndDateISO8601: String?
        public let newDurationMinutes: Int?
        public let newLocation: String?
        public let newNotes: String?
        public let newIsAllDay: Bool?

        public init(
            title: String,
            calendarName: String? = nil,
            startDateISO8601: String? = nil,
            endDateISO8601: String? = nil,
            newTitle: String? = nil,
            newCalendarName: String? = nil,
            newStartDateISO8601: String? = nil,
            newEndDateISO8601: String? = nil,
            newDurationMinutes: Int? = nil,
            newLocation: String? = nil,
            newNotes: String? = nil,
            newIsAllDay: Bool? = nil
        ) {
            self.title = title
            self.calendarName = calendarName
            self.startDateISO8601 = startDateISO8601
            self.endDateISO8601 = endDateISO8601
            self.newTitle = newTitle
            self.newCalendarName = newCalendarName
            self.newStartDateISO8601 = newStartDateISO8601
            self.newEndDateISO8601 = newEndDateISO8601
            self.newDurationMinutes = newDurationMinutes
            self.newLocation = newLocation
            self.newNotes = newNotes
            self.newIsAllDay = newIsAllDay
        }
    }

    public let name = "calendar.edit"
    public let capability = "Edit one matching calendar event title, calendar, time, location, notes, or all-day state. Requires explicit confirmation."
    public let mutatesState = true
    public let argumentSchema = #"{"title":"Dentist","calendarName":"optional current calendar","startDateISO8601":"optional current start ISO8601","endDateISO8601":"optional current end ISO8601","newTitle":"optional","newCalendarName":"optional","newStartDateISO8601":"optional ISO8601","newEndDateISO8601":"optional ISO8601","newDurationMinutes":"optional positive integer","newLocation":"optional","newNotes":"optional","newIsAllDay":"optional boolean"}"#

    public init() {}

    public func validate(_ arguments: Arguments) throws {
        _ = try normalizedTitle(arguments.title)
        _ = try optionalDate(arguments.startDateISO8601)
        _ = try optionalDate(arguments.endDateISO8601)
        let newTitle = arguments.newTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newCalendarName = arguments.newCalendarName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newStartDate = try optionalDate(arguments.newStartDateISO8601)
        let newEndDate = try optionalDate(arguments.newEndDateISO8601)
        if let duration = arguments.newDurationMinutes, duration <= 0 || duration > 24 * 60 {
            throw ToolExecutionError.invalidArguments("Calendar event newDurationMinutes must be in 1...1440.")
        }
        guard newTitle?.isEmpty == false
            || newCalendarName?.isEmpty == false
            || newStartDate != nil
            || newEndDate != nil
            || arguments.newDurationMinutes != nil
            || arguments.newLocation != nil
            || arguments.newNotes != nil
            || arguments.newIsAllDay != nil
        else {
            throw ToolExecutionError.invalidArguments("Calendar edit requires at least one new field.")
        }
        if let newTitle, newTitle.isEmpty {
            throw ToolExecutionError.invalidArguments("Calendar event newTitle cannot be blank.")
        }
        if let newCalendarName, newCalendarName.isEmpty {
            throw ToolExecutionError.invalidArguments("Calendar event newCalendarName cannot be blank.")
        }
        if let newStartDate, let newEndDate, newEndDate <= newStartDate {
            throw ToolExecutionError.invalidArguments("Calendar event new end must be after new start.")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        try validate(arguments)
        try EventKitToolSupport.requireAccess(to: .event)

        let eventStore = EKEventStore()
        let event = try matchingEvent(arguments: arguments, eventStore: eventStore)
        if let newTitle = arguments.newTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !newTitle.isEmpty {
            event.title = newTitle
        }
        if let newCalendarName = arguments.newCalendarName?.trimmingCharacters(in: .whitespacesAndNewlines), !newCalendarName.isEmpty {
            event.calendar = try selectedCalendar(newCalendarName, eventStore: eventStore)
        }
        let newStartDate = try optionalDate(arguments.newStartDateISO8601)
        let newEndDate = try optionalDate(arguments.newEndDateISO8601)
        if let newStartDate {
            event.startDate = newStartDate
        }
        if let newEndDate {
            event.endDate = newEndDate
        } else if let duration = arguments.newDurationMinutes {
            event.endDate = Calendar.current.date(byAdding: .minute, value: duration, to: event.startDate) ?? event.startDate
        }
        guard event.endDate > event.startDate else {
            throw ToolExecutionError.invalidArguments("Calendar event end must be after start.")
        }
        if arguments.newLocation != nil {
            event.location = arguments.newLocation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        if arguments.newNotes != nil {
            event.notes = arguments.newNotes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        if let newIsAllDay = arguments.newIsAllDay {
            event.isAllDay = newIsAllDay
        }

        try eventStore.save(event, span: .thisEvent, commit: true)
        let calendarName = event.calendar?.title ?? "Unknown calendar"
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Calendar event edited.",
            untrustedPayload: Self.payload(
                title: event.title ?? "Untitled event",
                calendarName: calendarName,
                startDate: event.startDate,
                endDate: event.endDate
            ),
            metadata: [
                "title": event.title ?? "Untitled event",
                "calendar": calendarName,
                "start": ISO8601DateFormatter().string(from: event.startDate),
                "end": ISO8601DateFormatter().string(from: event.endDate)
            ]
        )
    }

    static func payload(title: String, calendarName: String, startDate: Date, endDate: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return "Edited calendar event: [\(calendarName)] \(title) from \(formatter.string(from: startDate)) to \(formatter.string(from: endDate))"
    }

    private func matchingEvent(arguments: Arguments, eventStore: EKEventStore) throws -> EKEvent {
        let title = try normalizedTitle(arguments.title)
        let startDate = try optionalDate(arguments.startDateISO8601)
        let endDate = try optionalDate(arguments.endDateISO8601)
        let calendars = try selectedCalendars(arguments.calendarName, eventStore: eventStore)
        let range = searchRange(startDate: startDate, endDate: endDate)
        let predicate = eventStore.predicateForEvents(withStart: range.start, end: range.end, calendars: calendars)
        let matchingEvents = eventStore.events(matching: predicate).filter { event in
            (event.title ?? "").localizedCaseInsensitiveCompare(title) == .orderedSame
                && dateMatches(event.startDate, startDate)
                && dateMatches(event.endDate, endDate)
        }
        guard let event = matchingEvents.only else {
            if matchingEvents.isEmpty {
                throw ToolExecutionError.invalidArguments("Calendar event not found: \(title)")
            }
            throw ToolExecutionError.invalidArguments("Multiple matching calendar events found for: \(title)")
        }
        return event
    }

    private func selectedCalendars(_ calendarName: String?, eventStore: EKEventStore) throws -> [EKCalendar]? {
        guard let calendarName = calendarName?.trimmingCharacters(in: .whitespacesAndNewlines), !calendarName.isEmpty else {
            return nil
        }
        return [try selectedCalendar(calendarName, eventStore: eventStore)]
    }

    private func selectedCalendar(_ calendarName: String, eventStore: EKEventStore) throws -> EKCalendar {
        if let calendar = eventStore.calendars(for: .event).first(where: {
            $0.title.localizedCaseInsensitiveCompare(calendarName) == .orderedSame
        }) {
            return calendar
        }
        throw ToolExecutionError.invalidArguments("Calendar not found: \(calendarName)")
    }

    private func normalizedTitle(_ title: String) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ToolExecutionError.invalidArguments("Calendar event title is required.")
        }
        return normalized
    }

    private func optionalDate(_ value: String?) throws -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return try EventKitToolSupport.parseDate(value, default: Date())
    }

    private func searchRange(startDate: Date?, endDate: Date?) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        if let startDate {
            return (
                calendar.date(byAdding: .minute, value: -1, to: startDate) ?? startDate,
                calendar.date(byAdding: .day, value: 1, to: endDate ?? startDate) ?? (endDate ?? startDate)
            )
        }
        let now = Date()
        return (
            calendar.date(byAdding: .year, value: -5, to: now) ?? now,
            calendar.date(byAdding: .year, value: 5, to: now) ?? now
        )
    }

    private func dateMatches(_ actual: Date, _ expected: Date?) -> Bool {
        guard let expected else {
            return true
        }
        return abs(actual.timeIntervalSince(expected)) < 1
    }
}

public struct CalendarDeleteTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let title: String
        public let calendarName: String?
        public let startDateISO8601: String?
        public let endDateISO8601: String?

        public init(
            title: String,
            calendarName: String? = nil,
            startDateISO8601: String? = nil,
            endDateISO8601: String? = nil
        ) {
            self.title = title
            self.calendarName = calendarName
            self.startDateISO8601 = startDateISO8601
            self.endDateISO8601 = endDateISO8601
        }
    }

    public let name = "calendar.delete"
    public let capability = "Delete one matching calendar event. Requires explicit confirmation."
    public let mutatesState = true
    public let argumentSchema = #"{"title":"Dentist","calendarName":"optional calendar","startDateISO8601":"optional start ISO8601","endDateISO8601":"optional end ISO8601"}"#

    public init() {}

    public func validate(_ arguments: Arguments) throws {
        _ = try normalizedTitle(arguments.title)
        _ = try optionalDate(arguments.startDateISO8601)
        _ = try optionalDate(arguments.endDateISO8601)
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        try validate(arguments)
        try EventKitToolSupport.requireAccess(to: .event)

        let eventStore = EKEventStore()
        let event = try matchingEvent(arguments: arguments, eventStore: eventStore)
        let title = event.title ?? "Untitled event"
        let calendarName = event.calendar?.title ?? "Unknown calendar"
        let startDate = event.startDate ?? Date()
        let endDate = event.endDate ?? startDate
        try eventStore.remove(event, span: .thisEvent, commit: true)
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Calendar event deleted.",
            untrustedPayload: Self.payload(
                title: title,
                calendarName: calendarName,
                startDate: startDate,
                endDate: endDate
            ),
            metadata: [
                "title": title,
                "calendar": calendarName,
                "start": ISO8601DateFormatter().string(from: startDate),
                "end": ISO8601DateFormatter().string(from: endDate)
            ]
        )
    }

    static func payload(title: String, calendarName: String, startDate: Date, endDate: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return "Deleted calendar event: [\(calendarName)] \(title) from \(formatter.string(from: startDate)) to \(formatter.string(from: endDate))"
    }

    private func matchingEvent(arguments: Arguments, eventStore: EKEventStore) throws -> EKEvent {
        let title = try normalizedTitle(arguments.title)
        let startDate = try optionalDate(arguments.startDateISO8601)
        let endDate = try optionalDate(arguments.endDateISO8601)
        let calendars = try selectedCalendars(arguments.calendarName, eventStore: eventStore)
        let range = searchRange(startDate: startDate, endDate: endDate)
        let predicate = eventStore.predicateForEvents(withStart: range.start, end: range.end, calendars: calendars)
        let matchingEvents = eventStore.events(matching: predicate).filter { event in
            (event.title ?? "").localizedCaseInsensitiveCompare(title) == .orderedSame
                && dateMatches(event.startDate, startDate)
                && dateMatches(event.endDate, endDate)
        }
        guard let event = matchingEvents.only else {
            if matchingEvents.isEmpty {
                throw ToolExecutionError.invalidArguments("Calendar event not found: \(title)")
            }
            throw ToolExecutionError.invalidArguments("Multiple matching calendar events found for: \(title)")
        }
        return event
    }

    private func selectedCalendars(_ calendarName: String?, eventStore: EKEventStore) throws -> [EKCalendar]? {
        guard let calendarName = calendarName?.trimmingCharacters(in: .whitespacesAndNewlines), !calendarName.isEmpty else {
            return nil
        }
        if let calendar = eventStore.calendars(for: .event).first(where: {
            $0.title.localizedCaseInsensitiveCompare(calendarName) == .orderedSame
        }) {
            return [calendar]
        }
        throw ToolExecutionError.invalidArguments("Calendar not found: \(calendarName)")
    }

    private func normalizedTitle(_ title: String) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ToolExecutionError.invalidArguments("Calendar event title is required.")
        }
        return normalized
    }

    private func optionalDate(_ value: String?) throws -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return try EventKitToolSupport.parseDate(value, default: Date())
    }

    private func searchRange(startDate: Date?, endDate: Date?) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        if let startDate {
            return (
                calendar.date(byAdding: .minute, value: -1, to: startDate) ?? startDate,
                calendar.date(byAdding: .day, value: 1, to: endDate ?? startDate) ?? (endDate ?? startDate)
            )
        }
        let now = Date()
        return (
            calendar.date(byAdding: .year, value: -5, to: now) ?? now,
            calendar.date(byAdding: .year, value: 5, to: now) ?? now
        )
    }

    private func dateMatches(_ actual: Date, _ expected: Date?) -> Bool {
        guard let expected else {
            return true
        }
        return abs(actual.timeIntervalSince(expected)) < 1
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
