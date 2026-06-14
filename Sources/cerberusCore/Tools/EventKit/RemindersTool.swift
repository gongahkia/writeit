@preconcurrency import EventKit
import Foundation

public struct RemindersTool: AssistantTool {
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

    public init() {}

    public func run(arguments: Arguments) async throws -> ToolResult {
        try EventKitToolSupport.requireAccess(to: .reminder)

        let limit = EventKitToolSupport.clampLimit(arguments.limit)
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

    private func fetchReminders(eventStore: EKEventStore, predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func compareReminders(_ lhs: EKReminder, _ rhs: EKReminder) -> Bool {
        switch (lhs.dueDateComponents?.date, rhs.dueDateComponents?.date) {
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

    private func formatReminder(_ reminder: EKReminder) -> String {
        let dueDate = reminder.dueDateComponents?.date.map { ISO8601DateFormatter().string(from: $0) } ?? "no due date"
        let listName = reminder.calendar?.title ?? "Unknown list"
        let status = reminder.isCompleted ? "completed" : "open"
        return "- \(dueDate) [\(listName)] \(status): \(reminder.title ?? "Untitled reminder")"
    }
}
