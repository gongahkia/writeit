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

private struct ReminderSnapshot: Sendable {
    let title: String
    let listName: String
    let dueDate: Date?
    let isCompleted: Bool
}
