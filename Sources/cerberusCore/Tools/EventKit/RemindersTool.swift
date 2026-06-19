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

public struct RemindersEditTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let title: String
        public let listName: String?
        public let dueDateISO8601: String?
        public let newTitle: String?
        public let newListName: String?
        public let newNotes: String?
        public let newDueDateISO8601: String?
        public let newPriority: Int?

        public init(
            title: String,
            listName: String? = nil,
            dueDateISO8601: String? = nil,
            newTitle: String? = nil,
            newListName: String? = nil,
            newNotes: String? = nil,
            newDueDateISO8601: String? = nil,
            newPriority: Int? = nil
        ) {
            self.title = title
            self.listName = listName
            self.dueDateISO8601 = dueDateISO8601
            self.newTitle = newTitle
            self.newListName = newListName
            self.newNotes = newNotes
            self.newDueDateISO8601 = newDueDateISO8601
            self.newPriority = newPriority
        }
    }

    public let name = "reminders.edit"
    public let capability = "Edit one matching reminder title, list, notes, due date, or priority. Requires explicit confirmation."
    public let mutatesState = true
    public let argumentSchema = #"{"title":"Buy milk","listName":"optional current list","dueDateISO8601":"optional current due date","newTitle":"optional","newListName":"optional","newNotes":"optional","newDueDateISO8601":"optional","newPriority":"optional 0-9"}"#

    public init() {}

    public func validate(_ arguments: Arguments) throws {
        _ = try normalizedTitle(arguments.title)
        if let dueDateISO8601 = arguments.dueDateISO8601 {
            _ = try EventKitToolSupport.parseDate(dueDateISO8601, default: Date())
        }
        if let newTitle = arguments.newTitle {
            _ = try normalizedTitle(newTitle)
        }
        if let newDueDateISO8601 = arguments.newDueDateISO8601 {
            _ = try EventKitToolSupport.parseDate(newDueDateISO8601, default: Date())
        }
        if let newPriority = arguments.newPriority, !(0...9).contains(newPriority) {
            throw ToolExecutionError.invalidArguments("Reminder priority must be in 0...9.")
        }
        guard arguments.newTitle != nil
            || arguments.newListName != nil
            || arguments.newNotes != nil
            || arguments.newDueDateISO8601 != nil
            || arguments.newPriority != nil else {
            throw ToolExecutionError.invalidArguments("At least one reminder edit field is required.")
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
        let outcome = try await editReminder(
            eventStore: eventStore,
            predicate: predicate,
            title: title,
            dueDate: filtersDueDate ? dueDate : nil,
            arguments: arguments
        )

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Reminder edited.",
            untrustedPayload: Self.payload(title: outcome.title, listName: outcome.listName, dueDate: outcome.dueDate),
            metadata: [
                "title": outcome.title,
                "list": outcome.listName
            ]
        )
    }

    static func payload(title: String, listName: String, dueDate: Date?) -> String {
        let due = dueDate.map { ISO8601DateFormatter().string(from: $0) } ?? "no due date"
        return "Edited reminder: [\(listName)] \(title) due \(due)"
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
        guard !calendars.isEmpty else {
            throw ToolExecutionError.invalidArguments("Reminder list not found: \(listName)")
        }
        return calendars
    }

    private func selectedCalendar(_ listName: String, eventStore: EKEventStore) throws -> EKCalendar {
        let normalized = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ToolExecutionError.invalidArguments("Reminder list is required.")
        }
        guard let calendar = eventStore.calendars(for: .reminder).first(where: {
            $0.title.localizedCaseInsensitiveCompare(normalized) == .orderedSame
        }) else {
            throw ToolExecutionError.invalidArguments("Reminder list not found: \(normalized)")
        }
        return calendar
    }

    private func editReminder(
        eventStore: EKEventStore,
        predicate: NSPredicate,
        title: String,
        dueDate: Date?,
        arguments: Arguments
    ) async throws -> EditOutcome {
        let result = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let matches = (reminders ?? []).filter { reminder in
                    guard (reminder.title ?? "").localizedCaseInsensitiveCompare(title) == .orderedSame else {
                        return false
                    }
                    return matchesDueDate(reminder, dueDate: dueDate)
                }

                guard let reminder = matches.only else {
                    let message = matches.isEmpty
                        ? "No matching reminder found."
                        : "Multiple matching reminders found; include listName or dueDateISO8601."
                    continuation.resume(returning: Result<EditOutcome, ToolExecutionError>.failure(.invalidArguments(message)))
                    return
                }

                do {
                    if let newTitle = arguments.newTitle {
                        reminder.title = try normalizedTitle(newTitle)
                    }
                    if let newListName = arguments.newListName {
                        reminder.calendar = try selectedCalendar(newListName, eventStore: eventStore)
                    }
                    if let newNotes = arguments.newNotes {
                        reminder.notes = newNotes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    }
                    if let newDueDateISO8601 = arguments.newDueDateISO8601 {
                        let newDueDate = try EventKitToolSupport.parseDate(newDueDateISO8601, default: Date())
                        reminder.dueDateComponents = Calendar.current.dateComponents(
                            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
                            from: newDueDate
                        )
                    }
                    if let newPriority = arguments.newPriority {
                        reminder.priority = newPriority
                    }
                    try eventStore.save(reminder, commit: true)
                    continuation.resume(returning: Result<EditOutcome, ToolExecutionError>.success(
                        EditOutcome(
                            title: reminder.title ?? title,
                            listName: reminder.calendar?.title ?? "Unknown list",
                            dueDate: reminder.dueDateComponents?.date
                        )
                    ))
                } catch let error as ToolExecutionError {
                    continuation.resume(returning: Result<EditOutcome, ToolExecutionError>.failure(error))
                } catch {
                    continuation.resume(returning: Result<EditOutcome, ToolExecutionError>.failure(
                        .denied("Unable to save edited reminder: \(error.localizedDescription)")
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

    private struct EditOutcome: Sendable {
        let title: String
        let listName: String
        let dueDate: Date?
    }
}

public struct RemindersDeleteTool: AssistantTool {
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

    public let name = "reminders.delete"
    public let capability = "Delete one matching reminder. Requires explicit confirmation."
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
        let outcome = try await deleteReminder(
            eventStore: eventStore,
            predicate: predicate,
            title: title,
            dueDate: filtersDueDate ? dueDate : nil
        )

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: "Reminder deleted.",
            untrustedPayload: Self.payload(title: outcome.title, listName: outcome.listName, dueDate: outcome.dueDate),
            metadata: [
                "title": outcome.title,
                "list": outcome.listName
            ]
        )
    }

    static func payload(title: String, listName: String, dueDate: Date?) -> String {
        let due = dueDate.map { ISO8601DateFormatter().string(from: $0) } ?? "no due date"
        return "Deleted reminder: [\(listName)] \(title) due \(due)"
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
        guard !calendars.isEmpty else {
            throw ToolExecutionError.invalidArguments("Reminder list not found: \(listName)")
        }
        return calendars
    }

    private func deleteReminder(
        eventStore: EKEventStore,
        predicate: NSPredicate,
        title: String,
        dueDate: Date?
    ) async throws -> DeleteOutcome {
        let result = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let matches = (reminders ?? []).filter { reminder in
                    guard (reminder.title ?? "").localizedCaseInsensitiveCompare(title) == .orderedSame else {
                        return false
                    }
                    return matchesDueDate(reminder, dueDate: dueDate)
                }

                guard let reminder = matches.only else {
                    let message = matches.isEmpty
                        ? "No matching reminder found."
                        : "Multiple matching reminders found; include listName or dueDateISO8601."
                    continuation.resume(returning: Result<DeleteOutcome, ToolExecutionError>.failure(.invalidArguments(message)))
                    return
                }

                let outcome = DeleteOutcome(
                    title: reminder.title ?? title,
                    listName: reminder.calendar?.title ?? "Unknown list",
                    dueDate: reminder.dueDateComponents?.date
                )
                do {
                    try eventStore.remove(reminder, commit: true)
                    continuation.resume(returning: Result<DeleteOutcome, ToolExecutionError>.success(outcome))
                } catch {
                    continuation.resume(returning: Result<DeleteOutcome, ToolExecutionError>.failure(
                        .denied("Unable to delete reminder: \(error.localizedDescription)")
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

    private struct DeleteOutcome: Sendable {
        let title: String
        let listName: String
        let dueDate: Date?
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
