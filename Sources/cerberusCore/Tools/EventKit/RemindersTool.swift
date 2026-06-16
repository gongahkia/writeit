@preconcurrency import EventKit
import Foundation
import FoundationModels

public struct RemindersTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let listName: String?
        public let includeCompleted: Bool
        public let limit: Int

        public init(listName: String? = nil, includeCompleted: Bool = false, limit: Int = 10) {
            self.listName = listName
            self.includeCompleted = includeCompleted
            self.limit = limit
        }
    }

    public let name = "reminders.read"
    public let capability = "Read reminders from an optional reminders list."
    public let mutatesState = false
    public let argumentSchema = #"{"listName":"optional list name","includeCompleted":false,"limit":10}"#

    public init() {}

    public func run(arguments: Arguments) async throws -> ToolResult {
        try EventKitToolSupport.requireAccess(to: .reminder)

        let limit = ToolArgumentSupport.clampLimit(arguments.limit)
        let eventStore = EKEventStore()
        let calendars = selectedCalendars(arguments.listName, eventStore: eventStore)
        let predicate = eventStore.predicateForReminders(in: calendars)
        let reminders = await fetchReminders(eventStore: eventStore, predicate: predicate)
            .filter { arguments.includeCompleted || !$0.isCompleted }
            .sorted(by: compareReminders)
            .prefix(limit)

        let payload = reminders
            .map(formatReminder)
            .joined(separator: "\n")

        let count = reminders.count
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: count == 1 ? "Found 1 reminder." : "Found \(count) reminders.",
            untrustedPayload: payload,
            metadata: ["count": "\(count)"]
        )
    }

    private func selectedCalendars(_ listName: String?, eventStore: EKEventStore) -> [EKCalendar]? {
        guard let listName, !listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return eventStore.calendars(for: .reminder).filter {
            $0.title.localizedCaseInsensitiveCompare(listName) == .orderedSame
        }
    }

    private func fetchReminders(eventStore: EKEventStore, predicate: NSPredicate) async -> [ReminderSnapshot] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let snapshots = (reminders ?? []).map { reminder in
                    ReminderSnapshot(
                        title: reminder.title ?? "Untitled reminder",
                        listName: reminder.calendar?.title ?? "Unknown list",
                        dueDate: reminder.dueDateComponents?.date,
                        isCompleted: reminder.isCompleted
                    )
                }
                continuation.resume(returning: snapshots)
            }
        }
    }

    private func compareReminders(_ lhs: ReminderSnapshot, _ rhs: ReminderSnapshot) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case (.some(let lhsDate), .some(let rhsDate)):
            lhsDate < rhsDate
        case (.some, .none):
            true
        case (.none, .some):
            false
        case (.none, .none):
            lhs.title < rhs.title
        }
    }

    private func formatReminder(_ reminder: ReminderSnapshot) -> String {
        let dueDate = reminder.dueDate.map { ISO8601DateFormatter().string(from: $0) } ?? "no due date"
        let status = reminder.isCompleted ? "completed" : "open"
        return "- \(dueDate) [\(reminder.listName)] \(status): \(reminder.title)"
    }
}

public struct RemindersCreateTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let title: String
        public let listName: String?
        public let notes: String?
        public let dueDateISO8601: String?
        public let priority: Int?

        public init(
            title: String,
            listName: String? = nil,
            notes: String? = nil,
            dueDateISO8601: String? = nil,
            priority: Int? = nil
        ) {
            self.title = title
            self.listName = listName
            self.notes = notes
            self.dueDateISO8601 = dueDateISO8601
            self.priority = priority
        }
    }

    public let name = "reminders.create"
    public let capability = "Create a reminder in the default or named reminders list. Requires explicit confirmation."
    public let mutatesState = true
    public let argumentSchema = #"{"title":"Buy milk","listName":"optional list name","notes":"optional notes","dueDateISO8601":"optional ISO8601","priority":"optional 0-9"}"#

    public init() {}

    public func validate(_ arguments: Arguments) throws {
        _ = try normalizedTitle(arguments.title)
        if let dueDateISO8601 = arguments.dueDateISO8601 {
            _ = try EventKitToolSupport.parseDate(dueDateISO8601, default: Date())
        }
        if let priority = arguments.priority, !(0...9).contains(priority) {
            throw ToolExecutionError.invalidArguments("Reminder priority must be in 0...9.")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        try validate(arguments)
        try EventKitToolSupport.requireAccess(to: .reminder)

        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = try normalizedTitle(arguments.title)
        reminder.calendar = try selectedCalendar(arguments.listName, eventStore: eventStore)
        reminder.notes = arguments.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let dueDateISO8601 = arguments.dueDateISO8601 {
            let date = try EventKitToolSupport.parseDate(dueDateISO8601, default: Date())
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
                from: date
            )
        }
        if let priority = arguments.priority {
            reminder.priority = priority
        }

        try eventStore.save(reminder, commit: true)
        let listName = reminder.calendar?.title ?? "default list"
        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Reminder created.",
            untrustedPayload: Self.payload(title: reminder.title, listName: listName, dueDate: reminder.dueDateComponents?.date),
            metadata: [
                "title": reminder.title,
                "list": listName
            ]
        )
    }

    static func payload(title: String, listName: String, dueDate: Date?) -> String {
        let due = dueDate.map { ISO8601DateFormatter().string(from: $0) } ?? "no due date"
        return "Created reminder: [\(listName)] \(title) due \(due)"
    }

    private func normalizedTitle(_ title: String) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ToolExecutionError.invalidArguments("Reminder title is required.")
        }
        return normalized
    }

    private func selectedCalendar(_ listName: String?, eventStore: EKEventStore) throws -> EKCalendar {
        if let listName = listName?.trimmingCharacters(in: .whitespacesAndNewlines), !listName.isEmpty {
            if let calendar = eventStore.calendars(for: .reminder).first(where: {
                $0.title.localizedCaseInsensitiveCompare(listName) == .orderedSame
            }) {
                return calendar
            }
            throw ToolExecutionError.invalidArguments("Reminder list not found: \(listName)")
        }

        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw ToolExecutionError.denied("No default reminders list is available.")
        }
        return calendar
    }
}

public struct RemindersCompleteTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let title: String
        public let listName: String?
        public let dueDateISO8601: String?

        public init(title: String, listName: String? = nil, dueDateISO8601: String? = nil) {
            self.title = title
            self.listName = listName
            self.dueDateISO8601 = dueDateISO8601
        }
    }

    public let name = "reminders.complete"
    public let capability = "Mark one matching open reminder complete. Requires explicit confirmation."
    public let mutatesState = true
    public let argumentSchema = #"{"title":"Buy milk","listName":"optional list name","dueDateISO8601":"optional ISO8601 due date"}"#

    public init() {}

    public func validate(_ arguments: Arguments) throws {
        _ = try normalizedTitle(arguments.title)
        if let dueDateISO8601 = arguments.dueDateISO8601 {
            _ = try EventKitToolSupport.parseDate(dueDateISO8601, default: Date())
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        try validate(arguments)
        try EventKitToolSupport.requireAccess(to: .reminder)

        let eventStore = EKEventStore()
        let title = try normalizedTitle(arguments.title)
        let dueDate = try EventKitToolSupport.parseDate(arguments.dueDateISO8601, default: Date.distantPast)
        let filtersDueDate = arguments.dueDateISO8601?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let calendars = try selectedCalendars(arguments.listName, eventStore: eventStore)
        let predicate = eventStore.predicateForReminders(in: calendars)
        let outcome = try await completeReminder(
            eventStore: eventStore,
            predicate: predicate,
            title: title,
            dueDate: filtersDueDate ? dueDate : nil
        )

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Reminder completed.",
            untrustedPayload: Self.payload(title: outcome.title, listName: outcome.listName, dueDate: outcome.dueDate),
            metadata: [
                "title": outcome.title,
                "list": outcome.listName,
                "completedAt": ISO8601DateFormatter().string(from: outcome.completedAt)
            ]
        )
    }

    static func payload(title: String, listName: String, dueDate: Date?) -> String {
        let due = dueDate.map { ISO8601DateFormatter().string(from: $0) } ?? "no due date"
        return "Completed reminder: [\(listName)] \(title) due \(due)"
    }

    private func normalizedTitle(_ title: String) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ToolExecutionError.invalidArguments("Reminder title is required.")
        }
        return normalized
    }

    private func selectedCalendars(_ listName: String?, eventStore: EKEventStore) throws -> [EKCalendar]? {
        guard let listName = listName?.trimmingCharacters(in: .whitespacesAndNewlines), !listName.isEmpty else {
            return nil
        }
        let calendars = eventStore.calendars(for: .reminder).filter {
            $0.title.localizedCaseInsensitiveCompare(listName) == .orderedSame
        }
        guard calendars.isEmpty == false else {
            throw ToolExecutionError.invalidArguments("Reminder list not found: \(listName)")
        }
        return calendars
    }

    private func completeReminder(
        eventStore: EKEventStore,
        predicate: NSPredicate,
        title: String,
        dueDate: Date?
    ) async throws -> CompletionOutcome {
        let completedAt = Date()
        let result = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let matches = (reminders ?? []).filter { reminder in
                    guard reminder.isCompleted == false else {
                        return false
                    }
                    guard (reminder.title ?? "").localizedCaseInsensitiveCompare(title) == .orderedSame else {
                        return false
                    }
                    return self.matchesDueDate(reminder, dueDate: dueDate)
                }

                guard let reminder = matches.only else {
                    let message = matches.isEmpty
                        ? "No matching open reminder found."
                        : "Multiple matching reminders found; include listName or dueDateISO8601."
                    continuation.resume(returning: Result<CompletionOutcome, ToolExecutionError>.failure(.invalidArguments(message)))
                    return
                }

                reminder.isCompleted = true
                reminder.completionDate = completedAt

                do {
                    try eventStore.save(reminder, commit: true)
                    continuation.resume(returning: Result<CompletionOutcome, ToolExecutionError>.success(
                        CompletionOutcome(
                            title: reminder.title ?? title,
                            listName: reminder.calendar?.title ?? "Unknown list",
                            dueDate: reminder.dueDateComponents?.date,
                            completedAt: completedAt
                        )
                    ))
                } catch {
                    continuation.resume(returning: Result<CompletionOutcome, ToolExecutionError>.failure(
                        .denied("Unable to save completed reminder: \(error.localizedDescription)")
                    ))
                }
            }
        }
        return try result.get()
    }

    private func matchesDueDate(_ reminder: EKReminder, dueDate: Date?) -> Bool {
        guard let dueDate else {
            return true
        }
        guard let reminderDueDate = reminder.dueDateComponents?.date else {
            return false
        }
        return Calendar.current.isDate(reminderDueDate, inSameDayAs: dueDate)
    }

    private struct CompletionOutcome: Sendable {
        let title: String
        let listName: String
        let dueDate: Date?
        let completedAt: Date
    }
}

private struct ReminderSnapshot: Sendable {
    let title: String
    let listName: String
    let dueDate: Date?
    let isCompleted: Bool
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
